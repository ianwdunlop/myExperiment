# myExperiment: lib/workflow_processors/trident_xoml.rb
#
# Copyright (c) 2008 University of Manchester and the University of Southampton.
# See license.txt for details.

module WorkflowProcessors
  class TridentXoml < WorkflowProcessors::Interface
    
    # Begin Class Methods
    
    # These: 
    # - provide information about the Workflow Type supported by this processor,
    # - provide information about the processor's capabilites, and
    # - provide any general functionality.
    
    def self.display_name 
      "Trident (XOML)"
    end
    
    def self.content_type
      "trident_xoml"
    end
    
    def self.display_data_format
      "XOML"
    end
    
    def self.file_ext
      "xoml"
    end
    
    def self.can_infer_metadata?
      false
    end
    
    def self.can_generate_preview?
      false
    end
    
    # End Class Methods
    
    
    # Begin Object Initializer

    def initialize(workflow_definition)
      super(workflow_definition)
    end

    # End Object Initializer
    
    
    # Begin Instance Methods
    
    # These provide more specific functionality for a given workflow definition, such as parsing for metadata and image generation.
    
    
    
    # End Instance Methods
  end
end