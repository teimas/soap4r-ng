# encoding: UTF-8
# WSDL4R - Creating standalone server stub code from WSDL.
# Copyright (C) 2000-2007  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'wsdl/info'
require 'wsdl/soap/mappingRegistryCreator'
require 'wsdl/soap/methodDefCreator'
require 'wsdl/soap/classDefCreatorSupport'


module WSDL
module SOAP


class StandaloneServerStubCreator
  include ClassDefCreatorSupport

  attr_reader :definitions

  def initialize(definitions, name_creator, modulepath = nil)
    @definitions = definitions
    @name_creator = name_creator
    @modulepath = modulepath
  end

  def dump(service_name)
    warn("- Standalone stub can have only 1 port for now.  So creating stub for the first port and rests are ignored.")
    warn("- Standalone server stub ignores port location defined in WSDL.  Location is http://localhost:10080/ by default.  Generated client from WSDL must be configured to point this endpoint manually.")
    services = @definitions.service(service_name)
    unless services
      raise RuntimeError.new("service not defined: #{service_name}")
    end
    ports = services.ports
    if ports.empty?
      raise RuntimeError.new("ports not found for #{service_name}")
    end
    port = ports[0]
    if port.porttype.nil?
      raise RuntimeError.new("porttype not found for #{port}")
    end
    dump_porttype(port.porttype)
  end

private

  def dump_porttype(porttype)
    class_name = mapped_class_name(porttype.name, @modulepath)
    defined_const = {}
    methoddef = MethodDefCreator.new(@definitions, @name_creator, @modulepath, defined_const).dump(porttype.name)
    wsdl_name = @definitions.name ? @definitions.name.name : 'default'
    mrname = safeconstname(wsdl_name + 'MappingRegistry')
    c1 = XSD::CodeGen::ClassDef.new(class_name)
    c1.def_require("soap/rpc/standaloneServer")
    c1.def_code <<-EOD
Methods = [
#{methoddef.gsub(/^/, "  ")}
]
    EOD
    defined_const.each do |ns, tag|
      c1.def_const(tag, dq(ns))
    end
    c2 = XSD::CodeGen::ClassDef.new(class_name + "App",
      "::SOAP::RPC::StandaloneServer")
    c2.def_method("initialize", "*arg") do
      <<-EOD
        super(*arg)
        servant = #{class_name}.new
        #{class_name}::Methods.each do |definitions|
          opt = definitions.last
          if opt[:request_style] == :document
            @router.add_document_operation(servant, *definitions)
          else
            @router.add_rpc_operation(servant, *definitions)
          end
        end
        self.mapping_registry = #{mrname}::EncodedRegistry
        self.literal_mapping_registry = #{mrname}::LiteralRegistry
      EOD
    end
    c1.dump + "\n" + c2.dump + format(<<-EOD)

      if $0 == __FILE__
        # Change listen port.
        server = #{class_name}App.new('app', nil, '0.0.0.0', 10080)
        trap(:INT) do
          server.shutdown
        end
        server.start
      end
    EOD
  end
end


end
end
