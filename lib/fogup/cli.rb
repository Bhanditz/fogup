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
    def backup
      puts "Backing up #{src_desc} to #{dst_desc}...".bold
      src_dir.files.each do |src_file|
        backup_entity(src_file)
      end
      puts 'Done!'.bold
    end

    protected

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
      @connections[target] ||= begin
        credentials = config(target)[:credentials]
        Fog::Storage.new(credentials)
      end
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
