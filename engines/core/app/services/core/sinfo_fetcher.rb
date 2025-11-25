require "net/ssh"

module Core
  class SinfoFetcher
    CMD = "bash -lc 'module add slurm && sinfo -a'"

    def initialize(host:, user:, auth: {})
      @host = host
      @user = user
      @auth = auth
    end

    def call
      ssh_opts = {
        non_interactive: true,
        number_of_password_prompts: 0,
        timeout: 20,
        keepalive: true,
        keepalive_interval: 15,
        verify_host_key: :never
      }

      if @auth[:forward_agent]
        ssh_opts[:forward_agent] = true
      elsif @auth[:private_key_pem]
        key_path = write_temp_key(@auth[:private_key_pem])
        ssh_opts[:keys] = [key_path]
      elsif @auth[:key_path]
        ssh_opts[:keys] = [@auth[:key_path]]
      end

      Net::SSH.start(@host, @user, ssh_opts) do |ssh|
        stdout = ssh.exec!(CMD)
        return stdout.presence || "(пустой вывод)"
      end
    rescue => e
      "SSH error: #{e.class}: #{e.message}"
    ensure
      cleanup_temp_key
    end

    private

    def write_temp_key(pem)
      require "securerandom"
      @tmp_key_path = "/tmp/octo-#{SecureRandom.hex}"
      File.open(@tmp_key_path, "wb", 0o600) { |f| f.write(pem) }
      @tmp_key_path
    end

    def cleanup_temp_key
      File.delete(@tmp_key_path) if @tmp_key_path && File.exist?(@tmp_key_path)
    end
  end
end
