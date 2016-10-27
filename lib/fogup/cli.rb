require 'active_support/core_ext/hash'
require 'colorize'
require 'fog'
require 'fog/storage/openstack/models/files'
require 'mime-types'
require 'thor'
require 'yaml'

module Fogup
  class CLI < Thor
    default_task :backup

    desc 'backup', 'Backup one Fog storage location to another'
    method_option :prev, aliases: '-p', type: :string,
      desc: 'key of previous object to copy from'
    method_option :last, aliases: '-l', type: :string,
      desc: 'Key of last object to copy'
    method_option :list, aliases: '-r', type: :string,
      desc: 'Read object names to back up from list file'

    def backup
      puts "Backing up #{src_desc} to #{dst_desc}...".bold
      i = 0
      each_file_to_backup do |src_file|
        begin
          backup_entity(src_file)
        rescue Excon::Errors::Error => e
          puts "  #{e.class}; reconnecting".red.bold
          sleep 5
          connect(:src)
          connect(:dst)
          retry
        end
      end
      puts 'Done!'.bold
    end

    desc 'list', 'Output a list of all files in the src container'
    method_option :resume, aliases: '-r', type: :boolean,
      desc: 'Resume from last logged Swift marker'

    def list
      File.open(list_log_filename, 'a') do |list_log|
        puts "Listing files in #{src_desc} to #{list_log_filename}...".bold
        i = 0
        src_dir_files_from_marker(list_log_resume_marker).each do |src_file|
          i = i + 1
          puts "* [#{i}] #{src_file.key}"
          list_log << src_file.key + "\n"
        end
        puts 'Done!'.bold
      end
    end

    desc 'count', 'Count objects in container'
    method_option :dst, aliases: '-d', type: :boolean

    def count
      if options[:dst]
        i = 0
        dst_dir.files.each do |f|
          i = i + 1
          puts i.to_s
        end
      end
    end

    desc 'parallel', 'Generates a script for parallel backups'
    method_option :number, aliases: '-n', type: :numeric, required: true,
      desc: 'Number of instances to run'

    def parallel
      unless File.exists?(list_log_filename)
        puts "No log file #{list_log_filename} to examine. Run `fogup list` first."
        exit 1
      end

      total = `wc -l #{list_log_filename}`.to_i
      each = total / options[:number].to_i

      puts "#!/bin/bash"

      (1..options[:number].to_i).each do |instance|
        previous = if instance == 1
                     nil
                   else
                     line = (instance - 1) * each
                     `sed '#{line}q;d' #{list_log_filename}`.chomp
                   end
        last = if instance == options[:number].to_i
                 nil
               else
                 line = instance * each
                 `sed '#{line}q;d' #{list_log_filename}`.chomp
               end
        log = format("%0#{options[:number].to_s.length}d", instance)

        command = "bundle exec bin/fogup backup"
        command << " -p #{previous}" unless previous.nil?
        command << " -l #{last}" unless last.nil?
        command << " > log/fogup.#{log}.log 2>&1 &"
        puts command
      end
    end

    protected

    def each_file_to_backup
      if options[:list]
        File.open(options[:list], 'r').each_line do |line|
          key = line.chomp
          file = src_dir.files.head(key)
          next if file.nil?
          yield file
        end
      else
        src_dir_files_from_marker(options[:prev]).each do |f|
          yield f
          break if f.key == options[:last]
        end
      end
    end

    def list_log_resume_marker
      marker = `tail -n 1 #{list_log_filename}`
      puts "Resuming from marker #{marker}"
      marker.chomp
    end

    def list_log_filename
      'log/src_list.log'
    end

    def src_dir_files_from_marker(marker)
      Fog::Storage::OpenStack::Files.new(
        directory: src_dir,
        service: src_dir.service,
        marker: marker
      )
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
