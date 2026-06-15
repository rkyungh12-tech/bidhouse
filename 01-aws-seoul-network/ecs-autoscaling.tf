# ============================================================================
# [01-aws-seoul-network/ecs-autoscaling.tf] 이름표 엇박자 완전 정밀 교정본
# ============================================================================

resource "aws_appautoscaling_target" "ecs_service" {
  count = var.ecs_autoscaling_enabled ? 1 : 0 # [cite: 107, 108]

  min_capacity = var.ecs_autoscaling_min_capacity # 
  max_capacity = var.ecs_autoscaling_max_capacity # 

  # 🟢 [억까 방지] 유령 리소스 참조 대신 민조님의 실제 AWS 클러스터/서비스 이름으로 경로를 고정합니다.
  resource_id        = "service/${aws_ecs_cluster.smoke.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount" # 
  service_namespace  = "ecs"                      # 
}

resource "aws_appautoscaling_policy" "ecs_cpu_target_tracking" {
  count = var.ecs_autoscaling_enabled ? 1 : 0 # [cite: 109]

  name               = "bidhouse-prod-ecs-cpu-target-tracking"                     # [cite: 109]
  policy_type        = "TargetTrackingScaling"                                     # [cite: 109]
  resource_id        = aws_appautoscaling_target.ecs_service[0].resource_id        # [cite: 109]
  scalable_dimension = aws_appautoscaling_target.ecs_service[0].scalable_dimension # [cite: 109]
  service_namespace  = aws_appautoscaling_target.ecs_service[0].service_namespace  # [cite: 109]

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization" # [cite: 109]
    }

    target_value       = var.ecs_autoscaling_cpu_target_percent         # [cite: 109]
    scale_out_cooldown = var.ecs_autoscaling_scale_out_cooldown_seconds # [cite: 109]
    scale_in_cooldown  = var.ecs_autoscaling_scale_in_cooldown_seconds  # [cite: 109]
  }
}

resource "aws_appautoscaling_policy" "ecs_memory_target_tracking" {
  count = var.ecs_autoscaling_enabled ? 1 : 0 # [cite: 110]

  name               = "bidhouse-prod-ecs-memory-target-tracking"                  # [cite: 110]
  policy_type        = "TargetTrackingScaling"                                     # [cite: 110]
  resource_id        = aws_appautoscaling_target.ecs_service[0].resource_id        # [cite: 110]
  scalable_dimension = aws_appautoscaling_target.ecs_service[0].scalable_dimension # [cite: 110]
  service_namespace  = aws_appautoscaling_target.ecs_service[0].service_namespace  # [cite: 110]

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization" # [cite: 110]
    }

    target_value       = var.ecs_autoscaling_memory_target_percent      # [cite: 110]
    scale_out_cooldown = var.ecs_autoscaling_scale_out_cooldown_seconds # [cite: 110]
    scale_in_cooldown  = var.ecs_autoscaling_scale_in_cooldown_seconds  # [cite: 111]
  }
}