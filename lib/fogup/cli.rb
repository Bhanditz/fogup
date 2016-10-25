require 'active_support/core_ext/hash'
require 'colorize'
require 'fog'
#require 'fog/openstack'
require 'mime-types'
require 'thor'
require 'yaml'

module Fogup
  class CLI < Thor
    default_task :backup

    desc 'backup', 'Backup one Fog storage location to another'
    method_option :first, aliases: '-f', type: :numeric,
      desc: 'Index of first object to copy, starts at 1'
    method_option :last, aliases: '-l', type: :numeric,
      desc: 'Index of last object to copy, starts at 1'

    def backup
      puts "Backing up #{src_desc} to #{dst_desc}...".bold
      i = 0
      src_dir.files.each do |src_file|
        i = i + 1
        if backup?(i)
          # puts i.inspect.green
          backup_entity(src_file)
        else
          # puts i.inspect.red
        end
        break unless keep_backing_up?(i)
      end
      puts 'Done!'.bold
    rescue Excon::Errors::SocketError
      puts '  Excon::Errors::SocketError; reconnecting'.red.bold
      connect(:src)
      connect(:dst)
    end

    protected

    def backup?(index)
      if options[:first] && (index < options[:first])
        false
      elsif options[:last] && (index > options[:last])
        false
      else
        true
      end
    end

    def keep_backing_up?(index)
      if options[:last] && (index >= options[:last])
        false
      else
        true
      end
    end

    def src_desc
      description(:src)
    end

    def dst_desc
      description(:dst)
    end

    def description(target)
      config(target)[:credentials][:provider] + '/' + config(target)[:directory]
    end

    def backup_entity(src_file)
      puts "* #{src_file.key} (#{src_file.content_type})"

      if entity_is_directory?(src_file)
        puts '  directory, skipping'.yellow
      elsif !entity_exists_in_dst?(src_file)
        puts '  file does not exist, copying'.green
        backup_file(src_file)
      else
        puts '  file exists, skipping'.yellow
      end
    end

    def backup_file(src_file)
      dst_file = dst_dir.files.create(
        key: dst_key(src_file),
        body: src_file.body,
        public: true
      )
    rescue Errno::EISDIR
      puts '  but was a directory, skipping'.red
    end

    def dst_key(src_file)
      prefix = dst_config[:prefix] || ''
      "#{prefix}#{src_file.key}"
    end

    def entity_is_directory?(src_file)
      src_file.content_type == 'application/directory'
    end

    def entity_exists_in_dst?(src_file)
      !dst_dir.files.head(dst_key(src_file)).nil?
    end

    def src_conn
      connection(:src)
    end

    def dst_conn
      connection(:dst)
    end

    def connection(target)
      @connections ||= {}
      connect(target) unless @connections.key?(target)
      @connections[target]
    end

    def connect(target)
      credentials = config(target)[:credentials]
      @connections[target] = Fog::Storage.new(credentials)
    end

    def src_config
      config(:src)
    end

    def dst_config
      config(:dst)
    end

    def config(target)
      (@config ||= load_config)[target]
    end

    def src_dir
      directory(:src)
    end

    def dst_dir
      directory(:dst)
    end

    def directory(target)
      @directories ||= {}
      @directories[target] ||= begin
        dir_key = config(target)[:directory]
        connection(target).directories.get(dir_key)
      end
    end

    def load_config
      YAML.load_file(config_file_path).with_indifferent_access
    end

    def config_file_path
      File.expand_path('../../../fog.yml', __FILE__)
    end
  end
end
