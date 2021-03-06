
module Redcar
  class Project
    class DirController
      include Redcar::Tree::Controller
      
      def activated(tree, node)
        if node.leaf?
          FileOpenCommand.new(node.path).run
        end
      end
      
      class DragController
        include Redcar::Tree::Controller::DragController
        
        attr_reader :tree
        
        def initialize(tree)
          @tree = tree
        end
        
        def reorderable?
          false
        end
        
        def can_drop?(nodes, target, position)
          nodes.all? {|node| droppable?(node, target)}
        end
        
        def do_drop(nodes, target, position)
          paths = nodes.map {|node| node.path }
          non_nested_paths = remove_nested_paths(paths)
          non_nested_paths.each do |path|
            dir = target ? target.directory : tree.tree_mirror.path
            unless File.dirname(path) == dir
              FileUtils.mv(path, dir)
            end
          end
          tree.refresh
        end
        
        private
        
        def droppable?(from_node, target_node)
          # you can always drop into the top level of the tree
          return true if target_node == nil
          
          # can't drop a file/dir onto itself
          return false if from_node.path == target_node.path
          
          # can't drop a directory into its children
          !child_of?(from_node.path, target_node.path)
        end
        
        def child_of?(path, possible_child_path)
          possible_child_path =~ /^#{Regexp.escape(path)}\//
        end
        
        # Removes paths which are children of higher level paths also being
        # dragged.
        def remove_nested_paths(paths)
          sorted = paths.sort
          keep = [sorted.first]
          sorted[1..-1].each do |path|
            unless child_of?(keep.last, path)
              keep << path
            end
          end
          keep
        end
      end
      
      def drag_controller(tree)
        DragController.new(tree)
      end
      
      def right_click(tree, node)
        controller = self
        
        menu = Menu::Builder.build do
          item("New File")      { controller.new_file(tree, node) }
          item("New Directory") { controller.new_dir(tree, node)  }
          separator
          if tree.selection.length > 1
            dirs = tree.selection.map {|node| node.parent_dir }
            if dirs.uniq.length == 1
              item("Bulk Rename") { controller.rename(tree, node)   }
            end
          else
            item("Rename")      { controller.rename(tree, node)   }
          end
          item("Delete")        { controller.delete(tree, node)   }
          separator
          if DirMirror.show_hidden_files?
            item("Hide Hidden Files") do
              DirMirror.show_hidden_files = false
              tree.refresh
            end
          else
            item("Show Hidden Files") do
              DirMirror.show_hidden_files = true
              tree.refresh
            end
          end
        end
        
        Application::Dialog.popup_menu(menu, :pointer)
      end
      
      def new_file(tree, node)
        enclosing_dir = node ? node.directory : tree.tree_mirror.path
        new_file_name = uniq_name(enclosing_dir, "New File")
        new_file_path = File.join(enclosing_dir, new_file_name)
        FileUtils.touch(new_file_path)
        tree.refresh
        tree.expand(node)
        new_file_node = DirMirror::Node.create_from_path(new_file_path)
        tree.edit(new_file_node)
      end
      
      def new_dir(tree, node)
        enclosing_dir = node ? node.directory : tree.tree_mirror.path
        new_dir_name = uniq_name(enclosing_dir, "New Directory")
        new_dir_path = File.join(enclosing_dir, new_dir_name)
        FileUtils.mkdir(new_dir_path)
        tree.refresh
        tree.expand(node)
        new_dir_node = DirMirror::Node.create_from_path(new_dir_path)
        tree.edit(new_dir_node)
      end
      
      def rename(tree, node)
        nodes = tree.selection
        if nodes.length == 1
          single_rename(tree, node)
        else
          bulk_rename(tree, nodes)
        end
      end
      
      def single_rename(tree, node)
        if node.text =~ /^(.*)\.[^\.]+$/
          tree.edit(node, 0, $1.length)
        else
          tree.edit(node)
        end
      end
      
      def bulk_rename(tree, nodes)
        tab = Redcar.app.focussed_window.new_tab(HtmlTab)
        controller = BulkRenameController.new(tab, tree, nodes)
        tab.html_view.controller = controller
        tab.focus
      end
      
      class BulkRenameController
        include Redcar::HtmlController
        
        attr_reader :pairs, :match_pattern, :replace_pattern
        
        def initialize(tab, tree, nodes)
          @tab = tab
          @tree = tree
          @pairs = nodes.map {|node| [node, File.basename(node.path)] }
          @match_pattern = ""
          @replace_pattern = ""
        end
        
        def title
          "Bulk Rename"
        end
      
        def index
          rhtml = ERB.new(File.read(File.join(File.dirname(__FILE__), "..", "..", "views", "bulk_rename.html.erb")))
          rhtml.result(binding)
        end
        
        def refresh(new_match_pattern, new_replace_pattern)
          begin
            @match_pattern   = /#{new_match_pattern}/
          rescue
            return []
          end
          @replace_pattern = new_replace_pattern
          result = @pairs.map do |node, _|
            old_name = File.basename(node.path)
            new_name = transform_name(old_name)
            new_path = File.join(File.dirname(node.path), new_name)
            conflicts = (File.exist?(new_path) and new_name != old_name)
            legal     = (new_name != "" and legal_path?(new_path))
            [new_name, conflicts, legal]
          end
          result
        end
        
        def submit(params)
          @pairs.each do |node, _|
            old_name = File.basename(node.path)
            new_name = transform_name(old_name)
            next if old_name == new_name
            new_path = File.join(File.dirname(node.path), new_name)
            FileUtils.mv(node.path, new_path)
          end
          @tab.close
          @tree.refresh
        end
        
        private
        
        def transform_name(old_name)
          old_name.sub(match_pattern, replace_pattern)
        end
        
        def legal_path?(path)
          return true if File.exist?(path)
          
          begin
            FileUtils.touch(path)
            FileUtils.rm(path)
            return true
          rescue Errno::ENOENT
            return false
          end
        end
      end
      
      def delete(tree, _)
        nodes = tree.selection
        basenames = nodes.map {|node| File.basename(node.path) }
        msg = "Really delete #{basenames.join(", ")}?"
        result = Application::Dialog.message_box(msg, :type => :question, :buttons => :yes_no)
        if result == :yes
          nodes.each do |node|
            FileUtils.rm_rf(node.path)
          end
          tree.refresh
        end
      end
      
      def edited(tree, node, text)
        new_path = File.expand_path(File.join(File.dirname(node.path), text))
        return if node.path == new_path
        
        FileUtils.mv(node.path, new_path)
        tree.refresh
        new_node = DirMirror::Node.create_from_path(new_path)
        tree.select(new_node)
      end
      
      private
      
      def uniq_name(path, name)
        return name unless File.exist?(File.join(path, name))
        i = 1
        loop do
          new_name = name + " #{i}"
          return new_name unless File.exist?(File.join(path, new_name))
          i += 1
        end
      end
    end
  end
end

    
