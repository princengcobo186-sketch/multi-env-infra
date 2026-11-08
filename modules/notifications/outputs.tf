output "topic_arn" {
  description = "ARN of the alerts topic. Pass to other stacks as alarm_actions."
  value       = aws_sns_topic.alerts.arn
}

output "kms_key_arn" {
  description = "ARN of the key encrypting the topic."
  value       = aws_kms_key.alerts.arn
}
