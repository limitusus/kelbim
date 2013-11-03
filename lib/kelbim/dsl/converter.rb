require 'kelbim/policy-types'

module Kelbim
  class DSL
    class Converter
      class << self
        def convert(exported, instance_names)
          self.new(exported, instance_names).convert
        end
      end # of class methods

      def initialize(exported, instance_names)
        @exported = exported
        @instance_names = instance_names
      end

      def convert
        @exported.each.map {|vpc, load_balancers|
          output_ec2(vpc, load_balancers)
        }.join("\n")
      end

      private
      def output_ec2(vpc, load_balancers)
        arg_vpc = vpc ? vpc.inspect + ' ' : ''
        load_balancers = load_balancers.map {|name, load_balancer|
          output_load_balancer(vpc, name, load_balancer)
        }.join("\n").strip

        <<-EOS
ec2 #{arg_vpc}do
  #{load_balancers}
end
        EOS
      end

      def output_load_balancer(vpc, name, load_balancer)
        name = name.inspect
        is_internal = (load_balancer[:scheme] == 'internal')
        internal = is_internal ? ', :internal => true ' : ' '
        instances = output_instances(load_balancer[:instances], vpc).strip
        listeners = output_listeners(load_balancer[:listeners]).strip
        health_check = output_health_check(load_balancer[:health_check]).strip
        testcase = (is_internal and not load_balancer.fetch(:listeners, []).empty?) ? '' : ("\n    " + output_testcase(load_balancer).strip + "\n")

        out = <<-EOS
  load_balancer #{name}#{internal}do#{
    testcase}
    #{instances}

    #{listeners}

    #{health_check}
        EOS

        if vpc
          subnets = load_balancer[:subnets]
          subnets = subnets.map {|i| i.inspect }.join(",\n      ")

          out << "\n"
          out.concat(<<-EOS)
    subnets(
      #{subnets}
    )
          EOS

          security_groups = load_balancer[:security_groups]
          security_groups = security_groups.map {|i| i.inspect }.join(",\n      ")

          out << "\n"
          out.concat(<<-EOS)
    security_groups(
      #{security_groups}
    )
          EOS
        else
          availability_zones = load_balancer[:availability_zones]
          availability_zones = availability_zones.map {|i| i.inspect }.join(",\n      ")

          out << "\n"
          out.concat(<<-EOS)
    availability_zones(
      #{availability_zones}
    )
          EOS
        end

        out << "  end\n"
        return out
      end

      def output_testcase(load_balancer)
        dns_name = load_balancer[:dns_name]
        ports = load_balancer[:listeners].map {|i| i[:port] }

        out = <<-EOS
    test do
      host = #{dns_name.inspect}
        EOS

        ports.each do |port|
          out.concat(<<-EOS)

      expect {
        timeout(3) do
          socket = TCPSocket.open(host, #{port})
          socket.close if socket
        end
      }.not_to raise_error
          EOS
        end

        out.concat(<<-EOS)
    end
        EOS

        return out
      end

      def output_instances(instances, vpc)
        if instances.empty?
          instances = '# not registered'
        else
          instance_id_names = @instance_names[vpc] || {}

          instances = instances.map {|instance_id|
            instance_id_names.fetch(instance_id, instance_id).inspect
          }.join(",\n      ")
        end

        <<-EOS
    instances(
      #{instances}
    )
        EOS
      end

      def output_listeners(listeners)
        items = listeners.map {|listener|
          output_listener(listener).strip
        }.join("\n      ")

        <<-EOS
    listeners do
      #{items}
    end
        EOS
      end

      def output_listener(listener)
        protocol = listener[:protocol].inspect
        port = listener[:port]
        instance_protocol = listener[:instance_protocol].inspect
        instance_port = listener[:instance_port]
        policies = listener[:policies]
        server_certificate = listener[:server_certificate]

        out = "listener [#{protocol}, #{port}] => [#{instance_protocol}, #{instance_port}]"

        if policies.empty? and server_certificate.nil?
          return out
        end

        out << " do\n"

        unless policies.empty?
          policies_dsl = policies.map {|policy|
            PolicyTypes.convert_to_dsl(policy)
          }.join("\n        ")

          out << "        #{policies_dsl}\n"
        end

        if server_certificate
          out << "        server_certificate #{server_certificate.name.inspect}\n"
        end

        out << "      end"

        return out
      end

      def output_health_check(health_check)
        target = health_check[:target].inspect
        timeout = health_check[:timeout]
        interval = health_check[:interval]
        healthy_threshold = health_check[:healthy_threshold]
        unhealthy_threshold = health_check[:unhealthy_threshold]

        <<-EOS
    health_check do
      target #{target}
      timeout #{timeout}
      interval #{interval}
      healthy_threshold #{healthy_threshold}
      unhealthy_threshold #{unhealthy_threshold}
    end
        EOS
      end
    end # Converter
  end # DSL
end # Kelbim
