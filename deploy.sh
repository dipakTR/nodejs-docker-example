#!/bin/bash

# AWS ECS Deployment Script with Health Checks
set -e

# Configuration
CLUSTER_NAME="nodejs-docker-cluster"
SERVICE_NAME="nodejs-docker-service"
TASK_FAMILY="nodejs-docker-app"
ECR_REPO_URI="your-account.dkr.ecr.us-east-1.amazonaws.com/nodejs-docker-app"
TAG="latest"
AWS_REGION="us-east-1"

echo "🚀 Starting ECS deployment with health checks..."

# 1. Create ECS cluster
echo "📦 Creating ECS cluster..."
aws ecs create-cluster \
    --cluster-name $CLUSTER_NAME \
    --region $AWS_REGION

# 2. Create CloudWatch log group
echo "📊 Creating CloudWatch log group..."
aws logs create-log-group \
    --log-group-name "/ecs/$TASK_FAMILY" \
    --region $AWS_REGION || true

# 3. Register task definition with health check
echo "📋 Registering task definition with health check..."
aws ecs register-task-definition \
    --family $TASK_FAMILY \
    --network-mode awsvpc \
    --requires-compatibilities FARGATE \
    --cpu 256 \
    --memory 512 \
    --execution-role-arn "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/ecsTaskExecutionRole" \
    --container-definitions '[
        {
            "name": "nodejs-app",
            "image": "'$ECR_REPO_URI:$TAG'",
            "portMappings": [
                {
                    "containerPort": 8000,
                    "protocol": "tcp"
                }
            ],
            "essential": true,
            "healthCheck": {
                "command": [
                    "CMD-SHELL",
                    "curl -f http://localhost:8000/health || exit 1"
                ],
                "interval": 30,
                "timeout": 5,
                "retries": 3,
                "startPeriod": 60
            },
            "logConfiguration": {
                "logDriver": "awslogs",
                "options": {
                    "awslogs-group": "/ecs/'$TASK_FAMILY'",
                    "awslogs-region": "'$AWS_REGION'",
                    "awslogs-stream-prefix": "ecs"
                }
            },
            "environment": [
                {
                    "name": "PORT",
                    "value": "8000"
                },
                {
                    "name": "NODE_ENV",
                    "value": "production"
                }
            ]
        }
    ]' \
    --region $AWS_REGION

# 4. Create or update ECS service
echo "🔄 Creating/updating ECS service..."
aws ecs create-service \
    --cluster $CLUSTER_NAME \
    --service-name $SERVICE_NAME \
    --task-definition $TASK_FAMILY:1 \
    --desired-count 2 \
    --launch-type FARGATE \
    --health-check-grace-period-seconds 120 \
    --deployment-configuration '{
        "maximumPercent": 200,
        "minimumHealthyPercent": 50,
        "deploymentCircuitBreaker": {
            "enable": true,
            "rollback": true
        }
    }' \
    --network-configuration '{
        "awsvpcConfiguration": {
            "subnets": ["subnet-xxxxxxxx", "subnet-yyyyyyyy"],
            "securityGroups": ["sg-xxxxxxxxx"],
            "assignPublicIp": "ENABLED"
        }
    }' \
    --region $AWS_REGION || echo "Service already exists, updating..."

# 5. Monitor deployment
echo "👀 Monitoring deployment status..."
aws ecs wait services-stable \
    --cluster $CLUSTER_NAME \
    --services $SERVICE_NAME \
    --region $AWS_REGION

echo "✅ Deployment completed successfully!"

# 6. Show service status
echo "📊 Current service status:"
aws ecs describe-services \
    --cluster $CLUSTER_NAME \
    --services $SERVICE_NAME \
    --query 'services[0].{
        Status:status,
        Running:runningCount,
        Desired:desiredCount,
        Pending:pendingCount,
        LastEvent:events[0].message
    }' \
    --region $AWS_REGION
