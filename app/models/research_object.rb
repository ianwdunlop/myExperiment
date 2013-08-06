# myExperiment: app/models/research_object.rb
#
# Copyright (c) 2007-2013 The University of Manchester, the University of
# Oxford, and the University of Southampton.  See license.txt for details.

require 'rdf'
require 'rdf/raptor'
require 'yaml'

class ResearchObject < ActiveRecord::Base

  MANIFEST_PATH = ".ro/manifest.rdf"

  include ResearchObjectsHelper

  after_create :create_manifest

  belongs_to :user

  has_many :resources, :dependent => :destroy

  has_many :annotation_resources

  validates_presence_of :slug

  def uri
    Conf.base_uri + "/rodl/ROs/#{slug}/"
  end

  def creator_uri
    Conf.base_uri + "/users/#{user_id}"
  end

  def description

    ro_uri = RDF::URI(uri)

    graph = RDF::Graph.new

    graph << [ro_uri, RDF.type, RO.ResearchObject]
    graph << [ro_uri, RDF.type, ORE.Aggregation]
    graph << [ro_uri, ORE.isDescribedBy, ro_uri + MANIFEST_PATH]
    graph << [ro_uri, RDF::DC.created, created_at.to_datetime]
    graph << [ro_uri, RDF::DC.creator, RDF::URI(creator_uri)]

    graph << [RDF::URI(creator_uri), RDF.type, RDF::FOAF.Agent]

    if root_folder
      graph << [ro_uri, RO.rootFolder, RDF::URI(root_folder.uri)]
    end

    resources.each do |resource|

      if resource.is_aggregated
        graph << [ro_uri, ORE.aggregates, RDF::URI(resource.resource_uri)]
      end

      graph << resource.description
    end

    graph
  end

  def update_manifest!

    resources.reload

    manifest_body = pretty_rdf_xml(RDF::Writer.for(:rdfxml).buffer { |writer| writer << description })

    new_or_update_resource(
        :slug         => MANIFEST_PATH,
        :content_type => "application/rdf+xml",
        :data         => manifest_body,
        :force_write  => true) 
  end

  def manifest_resource
    resources.find(:first, :conditions => { :path => MANIFEST_PATH })
  end

  def root_folder
    resources.find(:first, :conditions => { :is_root_folder => true } )
  end

  def new_or_update_resource(opts = {})

    changed = []
    links = []
    location = nil

    content_type  = opts[:content_type]
    slug          = opts[:slug]
    path          = opts[:path]
    user_uri      = opts[:user_uri]
    data          = opts[:data]
    request_links = opts[:links] || {}

    if slug == ResearchObject::MANIFEST_PATH

      return [:forbidden, "Cannot overwrite the manifest", nil, []] unless opts[:force_write]

      manifest = create_resource(
        :path          => calculate_path(slug, content_type, request_links),
        :content_blob  => ContentBlob.new(:data => data),
        :creator_uri   => user_uri,
        :content_type  => content_type,
        :is_resource   => false,
        :is_aggregated => false,
        :is_proxy      => false,
        :is_annotation => false,
        :is_folder     => false)

      changed << manifest

    elsif content_type == "application/vnd.wf4ever.proxy"

      graph = load_graph(data)

      node           = graph.query([nil,  RDF.type,     ORE.proxy]).first_subject
      proxy_for_uri  = graph.query([node, ORE.proxyFor, nil      ]).first_object

      proxy = create_proxy(
        :path           => calculate_path(slug, content_type, request_links),
        :proxy_for_path => relative_uri(proxy_for_uri, uri),
        :proxy_in_path  => ".",
        :user_uri       => user_uri)

      proxy.update_graph!

      location =  proxy.uri
      links    << { :link => proxy_for_uri, :rel => ORE.proxyFor }
      changed  << proxy

    elsif content_type == "application/vnd.wf4ever.annotation"

      # Get information.

      graph = load_graph(data)

      aggregated_annotations = graph.query([nil, RDF.type, RO.AggregatedAnnotation])

      if aggregated_annotations.count != 1 # FIXME - add test case
        return [:unprocessable_entity, "The annotation must contain exactly one aggregated annotation", nil, []]
      end

      aggregated_annotation = aggregated_annotations.first_subject

      ao_body_statements = graph.query([aggregated_annotation, AO.body, nil])

      if ao_body_statements.count != 1 # FIXME - add test case
        return [:unprocessable_entity, "Annotations must contain exactly one annotation body", nil, []]
      end

      annotated_resources_statements = graph.query([aggregated_annotation, AO.annotatesResource, nil])

      if annotated_resources_statements.count == 0 # FIXME - add test case
        return [:unprocessable_entity, "Annotations must annotate one or more resources", nil, []]
      end

      ao_body_uri = ao_body_statements.first_object.to_s

      stub = create_annotation_stub(
        :user_uri       => user_uri,
        :ao_body_path   => relative_uri(ao_body_uri, uri),
        :resource_paths => annotated_resources_statements.map { |a| relative_uri(a.object, uri) } )

      annotated_resources_statements.each do |annotated_resource|
        links << { :link => annotated_resource.object, :rel => AO.annotatesResource }
      end

      stub.update_graph!

      links   << { :link => ao_body_uri, :rel => AO.body }
      changed << stub

    elsif content_type == "application/vnd.wf4ever.folder"

      folder = create_folder(slug, opts[:user_uri])

      location = folder.proxy.uri

      links << { :link => folder.resource_map.uri, :rel => ORE.isDescribedBy }
      links << { :link => folder.uri,              :rel => ORE.proxyFor      }

      changed << folder.proxy
      changed << folder.resource_map
      changed << folder

    elsif content_type == "application/vnd.wf4ever.folderentry"

      # Obtain information to create the folder entry.

      graph = load_graph(data)

      node           = graph.query([nil,  RDF.type,     RO.FolderEntry]).first_subject
      proxy_for_uri  = graph.query([node, ORE.proxyFor, nil           ]).first_object

      # FIXME - need to check if proxy_in and proxy_for actually exists and error if not

      proxy_for_path = relative_uri(proxy_for_uri, uri)
      proxy_in_path  = opts[:path]

      # Create the folder entry

      folder_entry = create_folder_entry(proxy_for_path, proxy_in_path, user_uri)

      location = folder_entry.uri

      links << { :link => proxy_for_uri, :rel => ORE.proxyFor }

      changed << folder_entry

    elsif request_links[AO.annotatesResource.to_s]

      path           = calculate_path(nil, content_type)
      ro_uri         = RDF::URI(uri)
      annotation_uri = ro_uri + path

      # Create an annotation body using the provided graph

      ao_body = create_aggregated_resource(
        :path         => calculate_path(slug, content_type, request_links),
        :data         => data,
        :content_type => content_type,
        :user_uri     => user_uri)

      stub = create_annotation_stub(
        :user_uri       => user_uri,
        :ao_body_path   => ao_body.path,
        :resource_paths => request_links[AO.annotatesResource.to_s].map { |resource| relative_uri(resource, uri) } )

      stub.update_graph!

      request_links[AO.annotatesResource.to_s].each do |annotated_resource_uri|
        links << { :link => annotated_resource_uri, :rel => AO.annotatesResource }
      end

      changed << stub
      changed << ao_body
      changed << ao_body.proxy

      links << { :link => stub.uri, :rel => AO.body }

      location = stub.uri

    else

      resource = create_aggregated_resource(
        :path         => calculate_path(slug, content_type, request_links),
        :data         => data,
        :content_type => content_type,
        :user_uri     => user_uri)

      changed << resource
    end

    if resource && content_type != "application/vnd.wf4ever.proxy" && !resource.is_manifest? && !request_links[AO.annotatesResource.to_s]

      proxy = resources.find(:first,
          :conditions => { :content_type   => 'application/vnd.wf4ever.proxy',
                           :proxy_in_path  => '.',
                           :proxy_for_path => resource.path })

      # Create a proxy for this resource if it doesn't exist.

      unless proxy
        proxy = create_proxy(
          :proxy_for_path => resource.path,
          :proxy_in_path  => ".",
          :user_uri       => user_uri)

        proxy.update_graph!
      end

      links << { :link => resource.uri, :rel => ORE.proxyFor }
      location = proxy.uri

      changed << proxy
    end

    location ||= resource.uri if resource

    [:created, nil, location, links, path, changed]
  end

  # opts[:path] - optional path to use for the proxy
  # opts[:proxy_for_path] - required
  # opts[:proxy_in_path] - required
  # opts[:user_uri] - optional

  def create_proxy(opts)

    # FIXME - these should be validations on the resource model
    throw "proxy_for_path required" unless opts[:proxy_for_path]
    throw "proxy_in_path required"  unless opts[:proxy_in_path]

    create_resource(
      :path           => opts[:path] || calculate_path(nil, 'application/vnd.wf4ever.proxy'),
      :is_proxy       => true,
      :proxy_for_path => opts[:proxy_for_path],
      :proxy_in_path  => opts[:proxy_in_path],
      :creator_uri    => opts[:user_uri],
      :content_type   => "application/vnd.wf4ever.proxy")
  end

  def create_annotation_stub(opts)

    # FIXME - these should be validations on the resource model
    throw "ao_body_path required"   unless opts[:ao_body_path]
    throw "resource_paths required" unless opts[:resource_paths]
    
    stub = create_resource(
      :path          => opts[:path] || calculate_path(nil, 'application/vnd.wf4ever.annotation'),
      :creator_uri   => opts[:user_uri],
      :content_type  => 'application/rdf+xml',
      :is_aggregated => true,
      :is_annotation => true,
      :ao_body_path  => opts[:ao_body_path])

    opts[:resource_paths].map do |resource_path|
      stub.annotation_resources.create(:resource_path => resource_path, :research_object => self)
    end

    stub
  end

  # opts = :slug, :body_graph, :creator_uri, :resources
  #
  def create_annotation(opts = {})

    # FIXME - these should be validations on the resource model
    throw "body_graph required"   unless opts[:body_graph]
    throw "resources required"    unless opts[:resources]
    throw "creator_uri required"  unless opts[:creator_uri]
    
    resources = opts[:resources]
    resources = [resources] unless resources.kind_of?(Array)

    if opts[:body_graph].kind_of?(RDF::Graph)
      data = create_rdf_xml { |graph| graph << opts[:body_graph] }
    else
      data = opts[:body_graph]
    end

    # Create an annotation body using the provided graph

    ao_body = create_aggregated_resource(
      :path         => calculate_path(opts[:slug], 'application/rdf+xml'),
      :data         => data,
      :content_type => "application/rdf+xml",
      :user_uri     => opts[:creator_uri])

    stub = create_annotation_stub(
      :user_uri       => opts[:creator_uri],
      :ao_body_path   => ao_body.path,
      :resource_paths => resources.map { |resource| relative_uri(resource, uri) } )

    stub.update_graph!

    stub

  end

  def create_aggregated_resource(opts = {})

    throw "user_uri required"     unless opts[:user_uri]
    throw "data required"         unless opts[:data]
    throw "content_type required" unless opts[:content_type]

    path = calculate_path(opts[:path], opts[:content_type])

    # Create a proxy for this resource.

    proxy = create_proxy(
      :proxy_for_path => path,
      :proxy_in_path  => ".",
      :user_uri       => opts[:user_uri])

    proxy.update_graph!

    # Create the resource.

    create_resource(
      :path          => path,
      :content_blob  => ContentBlob.new(:data => opts[:data]),
      :creator_uri   => opts[:user_uri],
      :content_type  => opts[:content_type],
      :is_resource   => true,
      :is_aggregated => true)
  end

  def create_resource_map(opts)

    create_resource(
      :path            => calculate_path(opts[:path], "application/vnd.wf4ever.folder"),
      :creator_uri     => opts[:user_uri],
      :content_type    => 'application/rdf+xml',
      :is_resource_map => true)

  end

  def create_folder_resource(opts)

    # Create a resource map for this folder

    resource_map = create_resource_map(:user_uri => opts[:user_uri])

    # Create the folder entry

    folder = create_resource(
      :path              => opts[:path],
      :creator_uri       => opts[:user_uri],
      :content_type      => "application/vnd.wf4ever.folder",
      :resource_map_path => resource_map.path,
      :is_aggregated     => true,
      :is_root_folder    => root_folder.nil?,
      :is_folder         => true)

    folder.update_graph!
    resource_map.update_graph!

    folder
  end

  def create_resource(attributes)

    resource = resources.find_by_path(attributes[:path]) || resources.new

    # FIXME - We need to know when we should be allowed to overwrite a
    # resource.  The RO structure needs to remain consistent.

    resource.attributes = attributes
    resource.save
    resource
  end

  def create_folder(path, user_uri)

    folder = create_folder_resource(
      :path     => path,
      :user_uri => user_uri)

    proxy = create_proxy(
      :proxy_for_path => folder.path,
      :proxy_in_path  => ".",
      :user_uri       => user_uri)

    folder
  end

  def create_folder_entry(path, parent_path, user_uri)

    folder_entry = create_resource(
      :path            => calculate_path(nil, 'application/vnd.wf4ever.folderentry'),
      :entry_name      => URI(path).path.split("/").last,
      :is_folder_entry => true,
      :proxy_in_path   => parent_path,
      :proxy_for_path  => path,
      :content_type    => 'application/vnd.wf4ever.folderentry',
      :creator_uri     => user_uri)

    if folder_entry.proxy_for
      folder_entry.proxy_for.update_attribute(:aggregated_by_path, parent_path)
    end

    folder_entry.update_graph!

    if folder_entry.proxy_for
      folder_entry.proxy_for.update_graph!
    end

    folder_entry
  end

  def find_using_path(path)
    bits = path.split("/")

    object = root_folder

    while (bit = bits.shift)
      folder_entries = object.proxies.select { |p| p.entry_name == bit }
      return nil if folder_entries.empty?
      object = folder_entries.first.proxy_for
    end

    object
  end

  def merged_annotation_graphs

    result = RDF::Graph.new

    resources.all(:conditions => { :is_annotation => true }).each do |annotation|
      ao_body = annotation.ao_body
      result << load_graph(ao_body.content_blob.data, ao_body.content_type)
    end

    result
  end

  def ore_structure_aux(entry, all_entries) #:nodoc:

    if entry.proxy_for.nil?
      {
        :name => entry.entry_name,
        :uri  => entry.proxy_for_path,
        :type => :remote
      }
    elsif entry.proxy_for.is_folder

      sub_entries = all_entries.select { |fe| fe.proxy_in_path == entry.proxy_for_path }

      { 
        :name => entry.entry_name,
        :type => :folder,
        :entries => sub_entries.map { |sub_entry| ore_structure_aux(sub_entry, all_entries) }
      }
    else
      {
        :name => entry.entry_name,
        :type => :file,
        :path => entry.proxy_for.path
      }
    end
  end

  def ore_structure

    return [] if root_folder.nil?

    all_entries = resources.find(:all, :conditions => { :is_folder_entry => true } )

    all_entries.select { |entry| entry.proxy_in_path == root_folder.path }.map do |entry|
      ore_structure_aux(entry, all_entries)
    end
  end

  def ore_directories_aux(prefix, structure)
    results = []

    structure.each do |entry|
      if entry[:type] == :folder
        results << "#{prefix}#{entry[:name]}"
        results += ore_directories_aux("#{prefix}#{entry[:name]}/", entry[:entries])
      end
    end

    results
  end

  def ore_directories
    ore_directories_aux('', ore_structure).sort
  end

  def ore_resources_aux(structure)
    results = []

    structure.each do |entry|

      case entry[:type]
      when :file
        results << entry
      when :folder
        results += ore_resources_aux(entry[:entries])
      end
    end

    results
  end

  def ore_resources
    ore_resources_aux(ore_structure)
  end

  def find_template_from_graph(graph, templates)

    templates.each do |name, template|
      parameters = match_ro_template(graph, template)
      return [template, parameters] if parameters
    end

    nil
  end

  def create_graph_using_ro_template(parameters, template)

    graph = RDF::Graph.new

    # Create the B-nodes.

    if template["bnodes"]
      template["bnodes"].each do |bnode|
        parameters[bnode] = RDF::Node.new(bnode)
      end
    end

    template["required_statements"].each do |statement|

      graph << [prepare_ro_template_value(statement[0], parameters),
                prepare_ro_template_value(statement[1], parameters),
                prepare_ro_template_value(statement[2], parameters)]
    end

    graph
  end

private

  def create_manifest #:nodoc:

    resources.create(:path => ResearchObject::MANIFEST_PATH,
                     :content_type => 'application/rdf+xml')

    update_manifest!
  end

  def match_ro_template(graph, template)

    parameters = {}

    # Work on a copy of the graph

    graph_copy = RDF::Graph.new

    graph.each do |statement|
      graph_copy << statement
    end

    template["required_statements"].each do |statement|

      # Find a statement that matches the current statement in the template.

      target = [prepare_ro_template_value(statement[0], parameters),
                prepare_ro_template_value(statement[1], parameters),
                prepare_ro_template_value(statement[2], parameters)]

      match = graph_copy.query(target).first


      return nil if match.nil?

      # Verify that there are no mismatches between existing parameters and found
      # parameters;  Then fill in newly defined parameters.

      return nil unless process_ro_template_parameter(statement[0], match[0], parameters)
      return nil unless process_ro_template_parameter(statement[1], match[1], parameters)
      return nil unless process_ro_template_parameter(statement[2], match[2], parameters)

      # Remove the current statement from the graph copy

      graph_copy.delete(match)
    end

    # Verify that all statements were consumed in processing the template.

    return nil unless graph_copy.empty?

    parameters
  end

  def process_ro_template_parameter(name, value, parameters)

    # Terms in the template can be one of three things:
    #
    #   1. A parameter, denoted by a symbol
    #   2. A URI, denoted by a string enclosed by angle brackets
    #   3. A literal, denoted by a string enclosed with double quote marks

    return true unless name.class == Symbol

    if parameters[name].nil?
      parameters[name] = value
      true
    else
      value == parameters[name]
    end
  end

  def prepare_ro_template_value(value, parameters)
    if value.class == Symbol
      parameters[value]
    elsif (value[0..0] == '<') && (value[-1..-1] == '>')
      RDF::URI.parse(value[1..-2])
    elsif (value[0..0] == '"') && (value[-1..-1] == '"')
      RDF::Literal.new(value[1..-2])
    else
      raise "Unknown template value: #{value}"
    end
  end

end