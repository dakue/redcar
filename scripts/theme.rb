

module Redcar
  class Theme
    # FIXME replace all this loading crap with a cached Marshal dump
    # (It will need to check the timestamps and reload if necessary).
    def self.scan_themes
      @themes_files = {}
      Dir["textmate/Themes/*"].each do |file|
        @themes_files[File.basename(file, ".tmTheme")] = file
      end
    end
  
    def self.load_themes
      scan_themes
      @themes_files.keys.each {|name| load_theme(name) }
    end
  
    def self.load_theme(name)
      scan_themes
      @themes ||= {}
      file = @themes_files[name]
      xml = IO.readlines(file).join
      plist = Redcar::Plist.plist_from_xml(xml)
      @themes[plist[0]['name']] = Redcar::Theme.new(plist[0])
    end
    
    def self.default_theme
      unless Redcar["theme/default_theme"]
        Redcar["theme/default_theme"] = "Mac Classic"
      end
      @default_theme ||= theme(Redcar["theme/default_theme"])
    end
    
    def self.set_theme(th)
      th = theme(th)
      @default_theme = th
      Redcar["theme/default_theme"] = th.name
      Redcar.current_window.all_tabs.each do |tab|
        tab.set_theme(th)
      end
    end
    
    def self.theme(name)
      @themes ||= {}
      scan_themes
      case name
      when String
        th = @themes[name]
        unless th
          if @themes_files.keys.include? name
            load_theme(name)
          else
            puts "no such theme"
          end
        end
      when Theme
        name
      end
    end
    
    def self.theme_names
      @themes_files.keys
    end
  end
end

Redcar.menu("_Options") do |menu|
  menu.command("Select Theme", :select_theme, nil, "") do |pane, tab|
    Redcar::Theme.scan_themes
    list = Redcar::GUI::List.new
    list.replace(Redcar::Theme.theme_names)
    
    dialog = Redcar::Dialog.build :title => "Choose Theme",
                                  :buttons => [:Apply, :cancel],
                                  :entry => [{:name => :list, :type => :list, :abs => list}]
    dialog.on_button(:cancel) { dialog.close }
    dialog.on_button(:Apply) do
      name = list.selected
      dialog.close
      puts "applying theme: #{name}"
      Redcar::Theme.set_theme(name)
    end
    list.on_double_click do |row|
      name = row
      dialog.close
      puts "applying theme: #{name}"
      Redcar::Theme.set_theme(name)
    end
    
    dialog.show :modal => true
  end
end
    
module Redcar
  class Theme
    attr_accessor :name, :uuid, :global_settings
  
    def initialize(hash)
      @name = hash['name']
      @uuid = hash['uuid']
      @global_settings = hash["settings"].find {|h| h.keys == ["settings"]}["settings"]
      @settings = hash["settings"].reject{|h| h.keys == ["settings"]}
    end
    
    # For a given scope finds all the settings in the theme which apply to it.
    def settings_for_scope(scope)
      applicables = []
      @settings.each do |setting|
        if setting['scope']
          if spec = applicable?(setting['scope'], scope)
            applicables << [spec, setting]
          end
        end
      end
      applicables.sort_by {|a| -a[0]}.map {|a| a[1]}
    end
    
    # Given a scope selector, returns its specificity. E.g keyword.if == 2 and string constant == 2
    def specificity(selector)
      selector.split(/\.|\s/).length
    end
    
    # Returns false if the selector is not applicable to the scope, and returns the specificity of the
    # selector if it is applicable.
    def applicable?(selector, scope)
      # split by commas (which are ORs)
      selector.split(',').each do |subselector|
        subselector = subselector.strip
        return specificity(subselector) if subselector == scope
        
        # split on spaces (which are ANDs)
        selector_components = subselector.split(' ')
        has_all = selector_components.inject(1) do |memo, comp|
          if scope.include? comp
            memo *= 1
          else
            memo *= 0
          end
        end
        spec = selector_components.inject(0) {|m, c| m += specificity(c) }
        return spec if has_all == 1
      end
      false
    end
    
    def self.parse_colour(str_colour)
      return nil unless str_colour
      if str_colour.length == 7
        Gdk::Color.parse(str_colour)
      elsif str_colour.length == 9
        # FIXME: what are the extra two hex values for? 
        # (possibly they are an opacity)
        Gdk::Color.parse(str_colour[0..6])
      end
    end
    
    def self.textmate_settings_to_pango_options(settings)
      options = { :foreground => settings["foreground"],
                  :background => settings["background"] }
      options = options.delete_if{|k, v| !v}
      settings["fontStyle"] ||= ""
      if settings["fontStyle"].include? "italic"
        options[:style] = Pango::STYLE_ITALIC
      end
      if settings["fontStyle"].include? "underline"
        options[:underline] = Pango::UNDERLINE_LOW
      end
      if settings["fontStyle"].include? "bold"
        options[:weight] = Pango::WEIGHT_BOLD
      end
      options
    end
  end
end