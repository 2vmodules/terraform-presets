This preset category is intended to roll out a minimum infrastructure solution that includes:

* EC2 instance to run the applications on
* EIP for the instance with direct access and basic security group rules
* S3 bucket for static files storage

This is mainly used for development environments.

Requirements before the deployment:

1. SSH authorized keys file content should be put into a Parameter Store secure string and the key name should be passed as "bastion_ssh_authorized_keys_secret" variable.