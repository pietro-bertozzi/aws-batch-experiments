output "job_queues" {
  value = { for k, q in aws_batch_job_queue.this : k => q.name }
}
