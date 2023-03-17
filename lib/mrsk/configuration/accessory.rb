class Mrsk::Configuration::Accessory
  delegate :argumentize, :argumentize_env_with_secrets, to: Mrsk::Utils

  attr_accessor :name, :specifics

  def initialize(name, config:)
    @name, @config, @specifics = name.inquiry, config, config.raw_config["accessories"][name]
  end

  def service_name
    "#{config.service}-#{name}"
  end

  def image
    specifics["image"]
  end

  def host
    specifics["host"] || raise(ArgumentError, "Missing host for accessory")
  end

  def port
    if specifics["port"].to_s.include?(":")
      specifics["port"]
    else
      "#{specifics["port"]}:#{specifics["port"]}"
    end
  end

  def port_args
    if specifics["port"]
      argumentize "--publish", port
    end
  end

  def labels
    default_labels.merge(specifics["labels"] || {})
  end

  def label_args
    argumentize "--label", labels
  end

  def env
    specifics["env"] || {}
  end

  def env_args
    argumentize_env_with_secrets env
  end

  def files
    specifics["files"]&.to_h do |local_to_remote_mapping|
      local_file, remote_file = local_to_remote_mapping.split(":")
      [ expand_local_file(local_file), expand_remote_file(remote_file) ]
    end || {}
  end

  def directories
    specifics["directories"]&.to_h do |host_to_container_mapping|
      host_relative_path, container_path = host_to_container_mapping.split(":")
      [ expand_host_path(host_relative_path), container_path ]
    end || {}
  end

  def volumes
    specific_volumes + remote_files_as_volumes + remote_directories_as_volumes
  end

  def volume_args
    argumentize "--volume", volumes
  end

  private
    attr_accessor :config

    def default_labels
      { "service" => service_name }
    end

    def expand_local_file(local_file)
      if local_file.end_with?("erb")
        with_clear_env_loaded { read_dynamic_file(local_file) }
      else
        Pathname.new(File.expand_path(local_file)).to_s
      end
    end

    def with_clear_env_loaded
      (env["clear"] || env).each { |k, v| ENV[k] = v }
      yield
    ensure
      (env["clear"] || env).each { |k, v| ENV.delete(k) }
    end

    def read_dynamic_file(local_file)
      StringIO.new(ERB.new(IO.read(local_file)).result)
    end

    def expand_remote_file(remote_file)
      service_name + remote_file
    end

    def specific_volumes
      specifics["volumes"] || []
    end

    def remote_files_as_volumes
      specifics["files"]&.collect do |local_to_remote_mapping|
        _, remote_file = local_to_remote_mapping.split(":")
        "#{service_data_directory + remote_file}:#{remote_file}"
      end || []
    end

    def remote_directories_as_volumes
      specifics["directories"]&.collect do |host_to_container_mapping|
        host_relative_path, container_path = host_to_container_mapping.split(":")
        [ expand_host_path(host_relative_path), container_path ].join(":")
      end || []
    end

    def expand_host_path(host_relative_path)
      "#{service_data_directory}/#{host_relative_path}"
    end

    def service_data_directory
      "$PWD/#{service_name}"
    end
end
