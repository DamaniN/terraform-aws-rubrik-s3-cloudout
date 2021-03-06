terraform {
  required_version = ">= 0.10.3" # introduction of Local Values configuration language feature
}

#############################
# Dynamic Variable Creation #
#############################
data "aws_caller_identity" "current" {}

###############################
# AWS IAM User and Permission #
###############################

resource "aws_iam_user" "rubrik" {
  name = var.iam_user_name
}

resource "aws_iam_policy" "cloud-out-permissions" {
  name = var.iam_policy_name

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:CreateBucket",
                "s3:ListAllMyBuckets"
            ],
            "Resource": "arn:aws:s3:::*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket",
                "s3:GetBucketLocation"
            ],
            "Resource": "arn:aws:s3:::${var.bucket_name}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject",
                "s3:DeleteObject",
                "s3:AbortMultipartUpload",
                "s3:ListMultipartUploadParts",
                "s3:RestoreObject"
            ],
            "Resource": "arn:aws:s3:::${var.bucket_name}/*"
        }
    ]
}

EOF
}

resource "aws_iam_user_policy_attachment" "rubrik-user" {
  user       = aws_iam_user.rubrik.name
  policy_arn = aws_iam_policy.cloud-out-permissions.arn
}

resource "aws_iam_access_key" "rubrik-user" {
  user = aws_iam_user.rubrik.name
}

###############################
#      Create S3 Bucket       #
###############################
resource "aws_s3_bucket" "archive_target" {
  bucket        = var.bucket_name
  force_destroy = var.bucket_force_destory
}

resource "aws_s3_bucket_public_access_block" "archive_target" {
  bucket                  = var.bucket_name
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

############################################
#      Create KMS Key for Encryption       #
############################################
resource "aws_kms_key" "rubrik-cloudout" {
  description = "KMS Key for Rubrik CloudOut."

  policy = <<EOF
  {
    "Version": "2012-10-17",
    "Id": "key-consolepolicy-3",
    "Statement": [
        {
            "Sid": "Enable IAM User Permissions",
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
            },
            "Action": "kms:*",
            "Resource": "*"
        },
        {
            "Sid": "Allow access for Key Administrators",
            "Effect": "Allow",
            "Principal": {
                "AWS": "${aws_iam_user.rubrik.arn}"
            },
            "Action": [
                "kms:Encrypt",
                "kms:Decrypt",
                "kms:ReEncrypt*",
                "kms:GenerateDataKey*",
                "kms:DescribeKey"
            ],
            "Resource": "*"
        },
        {
            "Sid": "Allow use of the key",
            "Effect": "Allow",
            "Principal": {
                "AWS": "${aws_iam_user.rubrik.arn}"
            },
            "Action": [
                "kms:Encrypt",
                "kms:Decrypt",
                "kms:ReEncrypt*",
                "kms:GenerateDataKey*",
                "kms:DescribeKey"
            ],
            "Resource": "*"
        }
    ]
}
  EOF
}

resource "aws_kms_alias" "a" {
  name          = "alias/${var.kms_key_alias}"
  target_key_id = aws_kms_key.rubrik-cloudout.key_id
}

############################################
#     Add Archive to Rubrik cluster        #
############################################

resource "rubrik_aws_s3_cloudout" "archive-target" {
  aws_access_key    = aws_iam_access_key.rubrik-user.id
  aws_secret_key    = aws_iam_access_key.rubrik-user.secret
  aws_bucket        = aws_s3_bucket.archive_target.bucket
  storage_class     = var.storage_class
  archive_name      = var.archive_name
  aws_region        = var.aws_region
  kms_master_key_id = aws_kms_key.rubrik-cloudout.key_id
  timeout           = var.timeout
}
