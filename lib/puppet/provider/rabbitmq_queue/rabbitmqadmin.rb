require 'json'
require 'puppet'
Puppet::Type.type(:rabbitmq_queue).provide(:rabbitmqadmin) do
  if Puppet::PUPPETVERSION.to_f < 3
    commands rabbitmqctl: 'rabbitmqctl'
    commands rabbitmqadmin: '/usr/local/bin/rabbitmqadmin'
  else
    has_command(:rabbitmqctl, 'rabbitmqctl') do
      environment HOME: '/tmp'
    end
    has_command(:rabbitmqadmin, '/usr/local/bin/rabbitmqadmin') do
      environment HOME: '/tmp'
    end
  end
  defaultfor feature: :posix

  def should_vhost
    if @should_vhost
      @should_vhost
    else
      @should_vhost = resource[:name].rpartition('@').last
    end
  end

  def self.all_vhosts
    rabbitmqctl('list_vhosts', '-q').split(%r{\n})
  end

  def self.all_queues(vhost)
    rabbitmqctl('list_queues', '-q', '-p', vhost, 'name', 'durable', 'auto_delete', 'arguments').split(%r{\n})
  end

  def self.instances
    resources = []
    all_vhosts.each do |vhost|
      all_queues(vhost).map do |line|
        next if line =~ %r{^federation:}
        name, durable, auto_delete, arguments = line.split("\t")
        # Convert output of arguments from the rabbitmqctl command to a json string.
        if !arguments.nil?
          arguments = arguments.gsub(%r{^\[(.*)\]$}, '').gsub(%r{\{("(?:.|\\")*?"),}, '{\1:').gsub(%r{\},\{}, ',')
          arguments = '{}' if arguments == ''
        else
          arguments = '{}'
        end
        queue = {
          durable: durable,
          auto_delete: auto_delete,
          arguments: JSON.parse(arguments),
          ensure: :present,
          name: format('%s@%s', name, vhost)
        }
        resources << new(queue) if queue[:name]
      end
    end
    resources
  end

  def self.prefetch(resources)
    packages = instances
    resources.keys.each do |name|
      if provider = packages.find { |pkg| pkg.name == name }
        resources[name].provider = provider
      end
    end
  end

  def exists?
    @property_hash[:ensure] == :present
  end

  def create
    vhost_opt = should_vhost ? "--vhost=#{should_vhost}" : ''
    name = resource[:name].rpartition('@').first
    arguments = resource[:arguments]
    arguments = {} if arguments.nil?
    rabbitmqadmin('declare',
                  'queue',
                  vhost_opt,
                  "--user=#{resource[:user]}",
                  "--password=#{resource[:password]}",
                  '-c',
                  '/etc/rabbitmq/rabbitmqadmin.conf',
                  "name=#{name}",
                  "durable=#{resource[:durable]}",
                  "auto_delete=#{resource[:auto_delete]}",
                  "arguments=#{arguments.to_json}")
    @property_hash[:ensure] = :present
  end

  def destroy
    vhost_opt = should_vhost ? "--vhost=#{should_vhost}" : ''
    name = resource[:name].rpartition('@').first
    rabbitmqadmin('delete', 'queue', vhost_opt, "--user=#{resource[:user]}", "--password=#{resource[:password]}", '-c', '/etc/rabbitmq/rabbitmqadmin.conf', "name=#{name}")
    @property_hash[:ensure] = :absent
  end
end
