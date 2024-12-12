terraform {
  required_version = ">= 1.8"

  required_providers {
    aws = {
        version = ">= 5.25.0"
        configuration_aliases = [aws.main, aws.us_east_1, aws.backup]
    }
    
    local    = ">= 2.2.2"
    null     = ">= 3.1.1"
    random   = ">= 3.4.3"
  }
}
