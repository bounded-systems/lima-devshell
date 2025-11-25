{
  description = "Project templates for bootstrapping";

  outputs = { self }:
    {
      templates = {
        # Add your templates here
        # Example:
        # my-template = {
        #   path = ./my-template;
        #   description = "Description of my template";
        # };

        # Default template
        # default = self.templates.my-template;
      };
    };
}

