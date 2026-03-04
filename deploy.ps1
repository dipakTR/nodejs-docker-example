# ECS Deployment Script for Windows PowerShell
param(
    [string]$ClusterName = "nodejs-docker-cluster",
    [string]$ServiceName = "nodejs-docker-service", 
    [string]$TaskFamily = "nodejs-docker-app",
    [string]$ImageUri = "your-account.dkr.ecr.us-east-1.amazonaws.com/nodejs-docker-app:latest",
    [string]$Region = "us-east-1",
    [string[]]$SubnetIds = @("subnet-xxxxxxxx", "subnet-yyyyyyyy"),
    [string]$SecurityGroupId = "sg-xxxxxxxxx"
)

Write-Host "🚀 Starting ECS deployment with health checks..." -ForegroundColor Green

# 1. Create ECS cluster
Write-Host "📦 Creating ECS cluster..." -ForegroundColor Yellow
try {
    aws ecs create-cluster --cluster-name $ClusterName --region $Region
} catch {
    Write-Host "Cluster might already exist" -ForegroundColor Yellow
}

# 2. Create CloudWatch log group  
Write-Host "📊 Creating CloudWatch log group..." -ForegroundColor Yellow
try {
    aws logs create-log-group --log-group-name "/ecs/$TaskFamily" --region $Region
} catch {
    Write-Host "Log group might already exist" -ForegroundColor Yellow
}

# 3. Get account ID for IAM role ARN
$AccountId = aws sts get-caller-identity --query Account --output text
$ExecutionRoleArn = "arn:aws:iam::${AccountId}:role/ecsTaskExecutionRole"

# 4. Create task definition JSON
$TaskDefinition = @{
    family = $TaskFamily
    networkMode = "awsvpc"
    requiresCompatibilities = @("FARGATE")
    cpu = "256"
    memory = "512"
    executionRoleArn = $ExecutionRoleArn
    containerDefinitions = @(
        @{
            name = "nodejs-app"
            image = $ImageUri
            portMappings = @(
                @{
                    containerPort = 8000
                    protocol = "tcp"
                }
            )
            essential = $true
            healthCheck = @{
                command = @(
                    "CMD-SHELL",
                    "curl -f http://localhost:8000/health || exit 1"
                )
                interval = 30
                timeout = 5
                retries = 3
                startPeriod = 60
            }
            logConfiguration = @{
                logDriver = "awslogs"
                options = @{
                    "awslogs-group" = "/ecs/$TaskFamily"
                    "awslogs-region" = $Region
                    "awslogs-stream-prefix" = "ecs"
                }
            }
            environment = @(
                @{
                    name = "PORT"
                    value = "8000"
                },
                @{
                    name = "NODE_ENV"
                    value = "production"
                }
            )
        }
    )
} | ConvertTo-Json -Depth 10

# Save task definition to file
$TaskDefinition | Out-File -FilePath "task-definition.json" -Encoding utf8

# 5. Register task definition
Write-Host "📋 Registering task definition with health check..." -ForegroundColor Yellow
aws ecs register-task-definition --cli-input-json "file://task-definition.json" --region $Region

# 6. Create network configuration
$NetworkConfig = @{
    awsvpcConfiguration = @{
        subnets = $SubnetIds
        securityGroups = @($SecurityGroupId)
        assignPublicIp = "ENABLED"
    }
} | ConvertTo-Json -Depth 3

# 7. Create deployment configuration  
$DeploymentConfig = @{
    maximumPercent = 200
    minimumHealthyPercent = 50
    deploymentCircuitBreaker = @{
        enable = $true
        rollback = $true
    }
} | ConvertTo-Json -Depth 3

# 8. Create or update service
Write-Host "🔄 Creating ECS service..." -ForegroundColor Yellow
try {
    aws ecs create-service --cluster $ClusterName --service-name $ServiceName --task-definition "${TaskFamily}:1" --desired-count 2 --launch-type FARGATE --health-check-grace-period-seconds 120 --deployment-configuration $DeploymentConfig --network-configuration $NetworkConfig --region $Region
} catch {
    Write-Host "Service might already exist, updating..." -ForegroundColor Yellow
}

# 9. Wait for service to stabilize
Write-Host "⏳ Waiting for service to stabilize..." -ForegroundColor Yellow
aws ecs wait services-stable --cluster $ClusterName --services $ServiceName --region $Region

# 10. Check service status
Write-Host "📊 Service deployment completed!" -ForegroundColor Green
aws ecs describe-services --cluster $ClusterName --services $ServiceName --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount,Events:events[0].message}' --region $Region

Write-Host "✅ Deployment script completed!" -ForegroundColor Green
Write-Host "Check AWS Console for detailed service status and logs." -ForegroundColor Cyan
