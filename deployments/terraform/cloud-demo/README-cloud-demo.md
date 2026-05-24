# Cloud Demo Terraform Runbook

This deployment creates two EC2 instances:

- App server: Banking API, PostgreSQL, Redis, RabbitMQ, PgBouncer, Prometheus, Grafana.
- k6 runner: remote load generator.

## Before running

1. Start AWS Learner Lab and update `~/.aws/credentials`.
2. Verify credentials:

```bash
aws sts get-caller-identity
```

3. Make sure SSH key exists:

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
```

## Apply

```bash
cd deployments/terraform/cloud-demo
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
```

Wait 5-10 minutes after apply. The app server seeds 100,000 accounts and 1,000,000 transactions automatically.

## Verify app server

```bash
terraform output -raw api_url
terraform output -raw grafana_url
terraform output -raw prometheus_url
```

Open Grafana using the output URL. Login: `admin / admin`.

## Run load test

```bash
$(terraform output -raw run_mixed_command)
```

or SSH to the runner:

```bash
$(terraform output -raw ssh_k6_command)
/home/ubuntu/run-mixed.sh
```

## Troubleshooting

SSH app server:

```bash
$(terraform output -raw ssh_app_command)
cd banking-peak-load-prototype
docker compose ps
docker compose logs app --tail=80
curl http://localhost:8080/metrics | head
curl http://localhost:9090/-/ready
```

Seed counts:

```bash
docker compose exec -T postgres psql -U postgres -d banking -c "SELECT COUNT(*) FROM accounts;"
docker compose exec -T postgres psql -U postgres -d banking -c "SELECT COUNT(*) FROM transactions;"
```

Expected counts:

- accounts: 100000
- transactions: 1000000

## Destroy

```bash
terraform destroy
```

## Post-apply readiness checks

After `terraform apply`, wait until cloud-init finishes:

```bash
$(terraform output -raw ssh_app_command)
cloud-init status --long
ls -l /home/ubuntu/cloud-demo-ready
cd banking-peak-load-prototype
docker compose ps
docker compose exec -T postgres psql -U postgres -d banking -c "SELECT COUNT(*) FROM accounts;"
docker compose exec -T postgres psql -U postgres -d banking -c "SELECT COUNT(*) FROM transactions;"
```

Expected:

- app, postgres, redis, rabbitmq, pgbouncer, prometheus, grafana are `Up`
- accounts = `100000`
- transactions = `1000000`

If Grafana shows `No data`, verify Prometheus first:

```bash
curl http://localhost:9090/api/v1/query?query=banking_api_requests_total
```

Then run the load test for at least 2-3 minutes before judging dashboard panels.
