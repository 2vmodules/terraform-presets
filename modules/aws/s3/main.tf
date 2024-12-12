locals {
  tags = merge({
    Env        = var.env
    tf-managed = true
    tf-module  = "aws/s3"
  }, var.tags)

  cors_rules_map = [
    {
      allowed_headers = []
      allowed_methods = ["GET"]
      allowed_origins = ["*"]
      expose_headers  = []
    },
    {
      allowed_headers = ["*"]
      allowed_methods = ["PUT", "HEAD"]
      allowed_origins = ["*"]
      expose_headers  = []
    }
  ]

}

module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "= 4.1.2"

  providers = {
    aws = aws.main
  }

  bucket                  = var.name
  acl                     = var.public ? "public-read" : "private"
  block_public_acls       = var.public ? false : true
  block_public_policy     = var.public ? false : true
  ignore_public_acls      = var.public ? false : true
  restrict_public_buckets = var.public ? false : true

  attach_policy = var.public ? true : false
  policy        = var.public ? data.aws_iam_policy_document.public.json : null

  cors_rule = var.public ? local.cors_rules_map : []

  versioning = {
    enabled = true
  }

  lifecycle_rule = [
    {
      id      = "expire-non-current-versions"
      enabled = true

      noncurrent_version_expiration = {
        days = 30
      }
    }
  ]

  replication_configuration = {
    role = aws_iam_role.replication.arn

    rules = [
      {
        id     = "s3-replication"
        status = var.replication ? "Enabled" : "Disabled"

        delete_marker_replication = true

        destination = {
          bucket        = module.s3_replication_bucket.s3_bucket_arn
          storage_class = "STANDARD"
        }
      },
    ]
  }

  control_object_ownership = true
  object_ownership         = var.object_ownership

  tags = local.tags
}

module "s3_replication_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "= 4.1.2"

  providers = {
    aws = aws.backup
  }

  bucket                  = format("%s-%s", var.name, "replicated")
  acl                     = "private"
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  versioning = {
    enabled = true
  }

  lifecycle_rule = [
    {
      id      = "expire-non-current-versions"
      enabled = true

      noncurrent_version_expiration = {
        days = 30
      }
    }
  ]

  control_object_ownership = true
  object_ownership         = var.object_ownership

  tags = local.tags

}

data "aws_iam_policy_document" "public" {
  statement {
    sid = "PublicReadGetObject"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = [
      "s3:GetObject",
    ]

    resources = [
      "${module.s3_bucket.s3_bucket_arn}/*",
    ]
  }
}

resource "aws_iam_role" "replication" {
  name = "s3-bucket-replication-${var.name}"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "s3.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
POLICY
}

resource "aws_iam_policy" "replication" {
  name = "s3-bucket-replication-${var.name}"

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:GetReplicationConfiguration",
        "s3:ListBucket"
      ],
      "Effect": "Allow",
      "Resource": [
        "${module.s3_bucket.s3_bucket_arn}"
      ]
    },
    {
      "Action": [
        "s3:GetObjectVersion",
        "s3:GetObjectVersionAcl"
      ],
      "Effect": "Allow",
      "Resource": [
        "${module.s3_bucket.s3_bucket_arn}/*"
      ]
    },
    {
      "Action": [
        "s3:ReplicateObject",
        "s3:ReplicateDelete"
      ],
      "Effect": "Allow",
      "Resource": "${module.s3_replication_bucket.s3_bucket_arn}/*"
    }
  ]
}
POLICY
}

resource "aws_iam_policy_attachment" "replication" {
  name       = "s3-bucket-replication-${var.name}"
  roles      = [aws_iam_role.replication.name]
  policy_arn = aws_iam_policy.replication.arn
}