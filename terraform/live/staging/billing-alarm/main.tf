terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# NOTE: AWS billing metrics are only published to us-east-1.
# This stack must be applied in us-east-1 regardless of where other
# resources live.

resource "aws_sns_topic" "billing_alerts" {
  name = "roadpass-exam-billing-alerts"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.billing_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "billing" {
  alarm_name          = "roadpass-exam-billing-threshold"
  alarm_description   = "Alert when estimated AWS charges exceed $${var.threshold_usd} USD"
  namespace           = "AWS/Billing"
  metric_name         = "EstimatedCharges"
  statistic           = "Maximum"
  period              = 86400 # 24 hours — billing metrics update once per day
  evaluation_periods  = 1
  threshold           = var.threshold_usd
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    Currency = "USD"
  }

  alarm_actions = [aws_sns_topic.billing_alerts.arn]
  ok_actions    = [aws_sns_topic.billing_alerts.arn]

  tags = var.tags
}
