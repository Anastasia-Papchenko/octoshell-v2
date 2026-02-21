# require "net/ssh"

# module Core
#   class SinfoFetcher
#     CMD = "bash -lc 'module add slurm && sinfo -a'"

#     def initialize(host:, user:, auth: {})
#       @host = host
#       @user = user
#       @auth = auth
#     end

#     def call
#       ssh_opts = {
#         non_interactive: true,
#         number_of_password_prompts: 0,
#         timeout: 20,
#         keepalive: true,
#         keepalive_interval: 15,
#         verify_host_key: :never
#       }

#       if @auth[:forward_agent]
#         ssh_opts[:forward_agent] = true
#       elsif @auth[:private_key_pem]
#         key_path = write_temp_key(@auth[:private_key_pem])
#         ssh_opts[:keys] = [key_path]
#       elsif @auth[:key_path]
#         ssh_opts[:keys] = [@auth[:key_path]]
#       end

#       Net::SSH.start(@host, @user, ssh_opts) do |ssh|
#         stdout = ssh.exec!(CMD)
#         return stdout.presence || "(пустой вывод)"
#       end
#     rescue => e
#       "SSH error: #{e.class}: #{e.message}"
#     ensure
#       cleanup_temp_key
#     end

#     private

#     def write_temp_key(pem)
#       require "securerandom"
#       @tmp_key_path = "/tmp/octo-#{SecureRandom.hex}"
#       File.open(@tmp_key_path, "wb", 0o600) { |f| f.write(pem) }
#       @tmp_key_path
#     end

#     def cleanup_temp_key
#       File.delete(@tmp_key_path) if @tmp_key_path && File.exist?(@tmp_key_path)
#     end
#   end
# end


require "net/ssh"
require "tempfile"

module Core
  class SinfoFetcher
    DEFAULT_CMD = "bash -lc 'module add slurm && sinfo -a'".freeze

    def initialize(cluster: nil, cluster_id: nil, host: nil, user: nil, auth: {}, cmd: DEFAULT_CMD)
      @cluster =
        cluster ||
        (cluster_id ? Core::Cluster.find(cluster_id) : nil)

      @host = host || @cluster&.host
      @user = user || @cluster&.admin_login
      @auth = auth
      @cmd  = cmd

      if @cluster && @auth.empty?
        if @cluster.private_key.present?
          @auth = { private_key_pem: @cluster.private_key }
        end
      end
    end

    def call
      raise ArgumentError, "host is required" if @host.blank?
      raise ArgumentError, "user is required" if @user.blank?

      ssh_opts = {
        non_interactive: true,
        number_of_password_prompts: 0,
        timeout: 20,
        keepalive: true,
        keepalive_interval: 15,
        verify_host_key: :never
      }

      key_tempfile = nil

      if @auth[:forward_agent]
        ssh_opts[:forward_agent] = true
      elsif @auth[:private_key_pem].present?
        key_tempfile = write_temp_key(@auth[:private_key_pem])
        ssh_opts[:keys] = [key_tempfile.path]
      elsif @auth[:key_path].present?
        ssh_opts[:keys] = [@auth[:key_path]]
      end

      Net::SSH.start(@host, @user, ssh_opts) do |ssh|
        stdout = ssh.exec!(@cmd)
        stdout.presence || "(пустой вывод)"
      end
    rescue => e
      "SSH error: #{e.class}: #{e.message}"
    ensure
      key_tempfile&.close
      key_tempfile&.unlink
    end

    private

    def write_temp_key(pem)
      tf = Tempfile.new(["octo-ssh-key", ""])
      tf.binmode
      tf.write(pem)
      tf.flush
      File.chmod(0o600, tf.path)
      tf
    end
  end
end
