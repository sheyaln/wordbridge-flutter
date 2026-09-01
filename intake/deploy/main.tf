# The wordbridge report intake, on Scaleway.
#
# Serverless Containers, Object Storage and Transactional Email. Scale to zero,
# so an intake nobody is reporting to costs the price of the objects in the
# bucket.
#
# Deliberately small. The service itself is S3 and SMTP and nothing else, so
# this file is the only part that knows which provider it is on: Cloud Run, GCS
# and SendGrid would be a rewrite of this file rather than of the service.

terraform {
  required_version = ">= 1.9"
  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.57"
    }
  }
}

variable "project_id" {
  type        = string
  description = "Scaleway project the intake lives in."
}

variable "region" {
  type    = string
  default = "fr-par"
}

variable "image" {
  type        = string
  description = "Full registry path and tag of the intake image."
}

variable "intake_token" {
  type        = string
  sensitive   = true
  description = "Bearer token, matching WORDBRIDGE_INTAKE_TOKEN in the app build."
}

variable "mail_to" {
  type        = string
  description = "Where a notification goes. Comma separated."
}

variable "mail_from" {
  type        = string
  description = "A sender on a domain verified in Transactional Email."
}

variable "smtp_password" {
  type      = string
  sensitive = true
}

variable "smtp_user" {
  type        = string
  description = "Scaleway TEM project id, which is what it uses as an SMTP user."
}

# Reports live here and nowhere else.
#
# Versioning is off on purpose: a report is written once and never edited, so
# versions would only keep copies of things somebody deleted deliberately.
resource "scaleway_object_bucket" "reports" {
  name       = "wordbridge-reports"
  project_id = var.project_id
  region     = var.region

  # A report is worth reading for as long as the version it describes is in
  # use, and after that it is a record of somebody's tablet nobody needs. Two
  # years, then it goes on its own.
  lifecycle_rule {
    id      = "expire"
    enabled = true
    expiration {
      days = 730
    }
  }
}

# Nothing in this bucket is public. It holds what people wrote about their
# children's communication devices.
resource "scaleway_object_bucket_acl" "reports" {
  bucket = scaleway_object_bucket.reports.id
  acl    = "private"
}

resource "scaleway_object_bucket_policy" "no_public_reads" {
  bucket = scaleway_object_bucket.reports.id
  policy = jsonencode({
    Version = "2023-04-17"
    Statement = [{
      Sid       = "RefuseAnythingUnencrypted"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        "${scaleway_object_bucket.reports.name}",
        "${scaleway_object_bucket.reports.name}/*",
      ]
      Condition = {
        Bool = { "aws:SecureTransport" = "false" }
      }
    }]
  })
}

# An application with write access to that bucket and nothing else. The intake
# never reads a report back, so it is not given permission to.
resource "scaleway_iam_application" "intake" {
  name        = "wordbridge-intake"
  description = "Writes reports to the bucket. No other rights."
}

resource "scaleway_iam_policy" "intake_writes" {
  name           = "wordbridge-intake-writes"
  application_id = scaleway_iam_application.intake.id

  rule {
    project_ids          = [var.project_id]
    permission_set_names = ["ObjectStorageObjectsWrite"]
  }
}

resource "scaleway_iam_api_key" "intake" {
  application_id = scaleway_iam_application.intake.id
  description    = "Object storage credentials for the intake container."
}

resource "scaleway_container_namespace" "intake" {
  name       = "wordbridge"
  project_id = var.project_id
  region     = var.region
}

resource "scaleway_container" "intake" {
  name         = "intake"
  namespace_id = scaleway_container_namespace.intake.id

  registry_image = var.image
  port           = 8080
  protocol       = "http1"

  # Scale to zero. Nobody is reporting anything most of the time, and a cold
  # start on a static binary is milliseconds — a caregiver pressing send will
  # not notice it.
  min_scale = 0

  # The ceiling that actually caps abuse. The per address limiter inside the
  # container stops one client filling this; this stops the bill.
  max_scale = 2

  # 256 MB. The body cap is 64 KB and the process holds one at a time, so this
  # is almost all headroom.
  memory_limit_bytes = 256 * 1024 * 1024
  cpu_limit          = 250

  # Reports come from tablets on the open internet, so this has to be public.
  # What protects it is the token, the rate limiter and this ceiling.
  privacy = "public"

  environment_variables = {
    S3_ENDPOINT = "s3.${var.region}.scw.cloud"
    S3_REGION   = var.region
    S3_BUCKET   = scaleway_object_bucket.reports.name
    SMTP_HOST   = "smtp.tem.scw.cloud"
    SMTP_PORT   = "587"
    MAIL_TO     = var.mail_to
    MAIL_FROM   = var.mail_from
  }

  secret_environment_variables = {
    INTAKE_TOKEN  = var.intake_token
    S3_ACCESS_KEY = scaleway_iam_api_key.intake.access_key
    S3_SECRET_KEY = scaleway_iam_api_key.intake.secret_key
    SMTP_USER     = var.smtp_user
    SMTP_PASS     = var.smtp_password
  }

  # Answers without touching storage or mail, so the check cannot be the thing
  # that wakes the bucket up or bills for a request nobody made.
  liveness_probe {
    http {
      path = "/healthz"
    }
    failure_threshold = 3
    interval          = "30s"
    timeout           = "5s"
  }
}

output "intake_url" {
  value       = "${scaleway_container.intake.public_endpoint}/v1/reports"
  description = "Pass this to the app build as WORDBRIDGE_INTAKE_URL."
}
