module Sawyer
  class Agent
    attr_reader :endpoint, :faraday

    # Determines what property of a resource contains the Array of links to
    # be processed.  Default: :_links
    #
    # Returns a Symbol.
    attr_accessor :links_property

    # Determines the default Relation name in a Schema that signifies the
    # top level collection of the resource.  Default: "all"
    #
    # Returns a String
    attr_reader :default_relation

    # Initializes an Agent.
    #
    # endpoint - String URL to start at.
    # faraday  - Optional Faraday::Connection.  `endpoint` will set
    #            Faraday::Connection#url_prefix.
    def initialize(endpoint, faraday = nil)
      @faraday = faraday || Faraday.new
      @faraday.url_prefix = (@endpoint = endpoint)
      
      @links_property       = :_links
      self.default_relation = "all"

      @schemas = @relations = nil

      yield @faraday if block_given?
    end

    # Public: Gets all of the top level Relations for this API.
    #
    # Returns a Hash of String keys and Sawyer::Relation values.
    def relations
      load_root if !@relations
      @relations
    end

    # Public: Gets all of the loaded Schemas for this API.
    #
    # Returns a Hash of String URL keys and Sawyer::Schema values.
    def schemas
      load_root if !@schemas
      @schemas
    end

    # Public: Gets a top level Relation by name.
    #
    # name - Either a String Relation name, or a Sawyer::Relation.
    #
    # Returns a Sawyer::Relation.
    def relation(name)
      return name if name.respond_to?(:request)
      load_root if !@relations
      @relations[name]
    end

    # Public: Loads or gets a loaded Schema by its href.  Schemas should
    # be referred to by the same href so that the same schema is not loaded
    # multiple times.
    #
    # href - A String URL to the JSON Schema.
    #
    # Returns a Sawyer::Schema.
    def schema(href)
      return schema(href.schema_href) if href.respond_to?(:schema_href)
      load_root if !@schemas
      @schemas[href] ||= begin
        res = @faraday.get(href)
        Sawyer::Schema.read(self, res.body, res.env[:url])
      end
    end
    
    # Public: Makes a request and loads a Resource based on the result.
    #
    # relation - A Sawyer::Relation or a String Relation name.  This determines
    #            the URL and method used.
    # resource - Optional body to send to the request.  This will be prepared
    #            for the request by #dump.
    #
    # Returns either a single Sawyer::Resource or an Array of Sawyer::Resources
    def request(relation, body = nil, *args)
      block = block_given? ? Proc.now : nil
      rel   = self.relation(relation)
      body  = dump(body)
      res   = @faraday.send(rel.method, rel.href, body, *args, &block)
      Sawyer::Response.new rel, res, load(res)
    end

    # Public: Determines if this Agent has hit the root endpoint yet.
    #
    # Returns a Boolean.
    def loaded?
      !(@relations && @schemas)
    end

    # Parses the response body into a Hash that is sent to initialize a
    # Resource.
    #
    # res - A Faraday::Response.
    # 
    # Returns a Hash or Array of Hashes.
    def load(res)
      Yajl.load(res.body, :symbolize_keys => true)
    end

    # Prepares the given data for the request.
    #
    # data - A Hash or Array of Hashes.
    #
    # Returns a String body for the request.
    def dump(data)
      return nil if !data
      Yajl.dump data
    end

    # Sets the default Relation.
    #
    # s - The String name of the Relation.
    #
    # Returns the frozen String name.
    def default_relation=(s)
      @default_relation = s.to_s.freeze
    end

    # Loads the root endpoint for the top level Schemas and Relations.
    #
    # Returns nothing.
    def load_root
      @relations = {}
      @schemas   = {}
      res  = @faraday.get @endpoint
      data = load(res)
      Relation.from(data[@links_property]).each do |rel|
        sch = schema(rel.schema_href)
        root_rel = @relations[rel.name] = sch.relations[sch.default_relation]
        root_rel.schema = sch
        sch.relations.each do |key, schema_rel|
          schema_rel.schema = sch
          next if key == sch.default_relation || schema_rel.href != root_rel.href
          @relations["#{rel.name}/#{key}"] = schema_rel
        end
      end
    end

    def inspect
      loaded? ?
        %(#<%s @endpoint="%s" (unloaded)>) % [
          self.class,
          @endpoint
        ] :
        %(#<%s @endpoint="%s">) % [
          self.class,
          @endpoint
        ]
    end
  end
end
