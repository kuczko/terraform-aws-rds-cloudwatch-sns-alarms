data "aws_caller_identity" "default" {}

locals {
  sns_topic = var.sns_topic == "" ? aws_sns_topic.default.arn : var.sns_topic
}

module "db_alarm_topic" {
  source      = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.19.2"
  namespace   = var.namespace
  name        = "${var.name}-alarms"
  stage       = var.stage
  environment = var.environment
  delimiter   = var.delimiter
  attributes  = var.attributes
}

resource "aws_sns_topic" "default" {
  count       = var.sns_topic == "" ? 1 : 0
  name_prefix = module.db_alarm_topic.id
}

resource "aws_db_event_subscription" "default" {
  name_prefix = "rds-event-sub"
  sns_topic   = local.sns_topic

  source_type = "db-instance"
  source_ids  = ["${var.db_instance_id}"]

  event_categories = [
    "failover",
    "failure",
    "low storage",
    "maintenance",
    "notification",
    "recovery",
  ]

  depends_on = ["aws_sns_topic_policy.default"]
}

resource "aws_sns_topic_policy" "default" {
  arn    = local.sns_topic
  policy = "${data.aws_iam_policy_document.sns_topic_policy.json}"
}

data "aws_iam_policy_document" "sns_topic_policy" {
  policy_id = "__default_policy_ID"

  statement {
    sid = "__default_statement_ID"

    actions = [
      "SNS:Subscribe",
      "SNS:SetTopicAttributes",
      "SNS:RemovePermission",
      "SNS:Receive",
      "SNS:Publish",
      "SNS:ListSubscriptionsByTopic",
      "SNS:GetTopicAttributes",
      "SNS:DeleteTopic",
      "SNS:AddPermission",
    ]

    effect    = "Allow"
    resources = [local.sns_topic]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceOwner"

      values = [
        "${data.aws_caller_identity.default.account_id}",
      ]
    }
  }

  statement {
    sid       = "Allow CloudwatchEvents"
    actions   = ["sns:Publish"]
    resources = [local.sns_topic]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }

  statement {
    sid       = "Allow RDS Event Notification"
    actions   = ["sns:Publish"]
    resources = [local.sns_topic]

    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }
  }
}
