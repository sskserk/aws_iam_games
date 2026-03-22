# Awide Platform on AWS – Architecture and Operations Guide

Applies to: Awide platform AMI deployment on AWS

---

## 1. Purpose and Scope

This document describes how the Awide platform product is deployed and operated on Amazon Web Services (AWS) based on the provided reference architecture.

It is intended for:

- Cloud / platform engineers operating the Awide platform on AWS.
- Security and compliance teams reviewing the architecture.
- DevOps / SRE teams responsible for monitoring, logging, and diagnostics.

The document focuses on the AWS-side architecture and responsibilities of the Awide platform. Application-level behaviors of the Awide platform are out of scope except where they affect infrastructure choices. Corresponding documentation can be found on the company site.

---

## 2. High-Level Architecture Overview

At a high level, the Awide platform runs as follows:

- The product is distributed as an **AWS Marketplace AMI**, which is used to launch an **Awide platform EC2 instance** inside a customer-managed **VPC**.
- On that EC2 instance, an **Update Agent** is responsible for retrieving container images and release metadata from **awidelabs.io** and **Private Docker Repository ** over the internet.
- The Update Agent manages one or more **application containers** running on the EC2 instance.
- An **Agent** component on the EC2 host collects logs and host-level metrics.
- Application and platform logs are written to a dedicated **Logs S3 bucket** and/or **Amazon CloudWatch Logs**.
- **CloudWatch** is also used for host and platform metrics.
- **Amazon Kinesis Data Firehose** is used to deliver logs from CloudWatch to the **S3 logs bucket** for temporary storage and analytic purposes.
- Application state and configuration are stored in an **Amazon RDS for PostgreSQL** database.
- **IAM roles and policies** are used to govern access between components and AWS services.

The entire solution can deployed within a chosen AWS Region but can be replicated to others if required.

---

## 3. Components and Responsibilities

### 3.1 AWS Marketplace AMI – Awide Platform

- **Type:** AMI product in AWS Marketplace.
- **Purpose:** Provides a pre-configured EC2 image that includes:
  - Base OS and runtime dependencies.
  - The Awide platform host components (Update Agent, Agent, container runtime, bootstrap logic).
- **Ownership:** Managed, patched, and updated by the Awide vendor via AMI version updates and container releases.
- **Customer responsibilities:**
  - Subscribing to the AMI in AWS Marketplace.
  - Launching EC2 instances from the AMI in appropriate subnets.
  - Applying security and compliance controls in their AWS account (network, IAM, logging, backups, etc.).

### 3.2 VPC

- **Type:** Customer-managed Virtual Private Cloud.
- **Purpose:** Provides network isolation and routing controls for the Awide platform.
- **Typical design (recommended):**
  - One or more **private subnets** for the Awide EC2 instance(s).
  - One or more **public subnets** containing NAT gateway(s) (if outbound internet connectivity is needed).
  - VPC endpoints for services such as S3, CloudWatch Logs, and Kinesis Firehose when using a private / restricted egress design.
- **Key configuration points:**
  - **CIDR range** sized to allow for growth and additional components.
  - **Route tables** to control outbound access to the internet (via IGW or NAT).
  - **Network ACLs** implementing coarse-grained allow/deny rules, typically default-allow for internal traffic and restricted for inbound internet flows.

### 3.3 EC2 Instance – Awide Platform Host

- **Type:** Amazon EC2 instance launched from the Awide Marketplace AMI.
- **Major responsibilities:**
  - Runs the **Update Agent** service.
  - Runs the **container runtime** (e.g., Docker or containerd) and Awide application containers.
  - Runs the **Agent** responsible for collecting logs and metrics.
  - Establishes network connectivity to:
    - External update sources (awidelabs.io and Private Docker Repository ).
    - RDS PostgreSQL database (SQL access).
    - S3, CloudWatch, and Kinesis Data Firehose for logging and metrics.
- **Instance profile (IAM role):**
  - Grants the EC2 host permission to access S3, CloudWatch Logs, CloudWatch Metrics, and Firehose as needed.
  - Should not allow direct IAM user actions; use least-privilege, scoped resource ARNs, and condition keys.
- **Storage:**
  - Root EBS volume from the AMI.
  - Optional additional EBS volumes for container storage, caches, and transient logs.

### 3.4 Update Agent

- **Runs on:** Awide platform EC2 instance.
- **Purpose:** Manage product lifecycle and updates by:
  - Periodically checking **awidelabs.io** (releases metadata endpoint) for new versions.
  - Pulling container images from **Private Docker Repository **.
  - Orchestrating deployment, restart, or rollback of Awide containers.
- **Network flows:**
  - Outbound HTTPS to `https://awidelabs.io`.
  - Outbound HTTPS to Private Docker Repository  endpoints (e.g., `registry.awidelabs.io`).
- **Operational concerns:**
  - Should honor corporate proxy settings if required.
  - Should log update activity to the local system and to CloudWatch or S3 for traceability.

### 3.5 Application Containers

- **Runs on:** Awide EC2 host under control of the Update Agent.
- **Purpose:** Host the core Awide application services.
- **Interactions:**
  - Access **RDS PostgreSQL** via SQL for application data.
  - Emit application logs to local stdout / files, which are then collected by the Agent and forwarded to S3 and/or CloudWatch Logs.
  - Expose service endpoints either internally (within the VPC) or via an external load balancer/API gateway, depending on deployment design (not shown in diagram, configurable by the customer).

### 3.6 Agent (Monitoring / Logging)

- **Runs on:** Awide EC2 host.
- **Purpose:**
  - Collect and ship **application logs**, **host logs**, and **host-level metrics** to AWS services.
- **Outputs:**
  - Sends logs and metrics to **CloudWatch**.
  - Optionally writes or forwards logs directly to the **Logs S3 bucket**.
- **Examples of collected data:**
  - Container stdout/stderr.
  - System logs (e.g., `/var/log`).
  - CPU, memory, disk, and network metrics.
  - Application-specific custom metrics, if configured.

### 3.7 Logs Bucket – Amazon S3

- **Type:** Dedicated S3 bucket for long-term log storage.
- **Sources:**
  - Direct log uploads from the Agent.
  - Deliveries from **Kinesis Data Firehose** (sourced from CloudWatch Logs).
- **Use cases:**
  - Long-term, low-cost archival storage of logs.
  - Data lake / analytics (e.g., Athena, Glue, or external SIEM ingestion).
- **Configuration considerations:**
  - **Bucket naming and partitioning** (e.g., prefix by `year=YYYY/month=MM/day=DD` or `service=` and `env=` for analytics).
  - **Lifecycle policies** (transition to infrequent access / Glacier, retention limits).
  - **Server-side encryption** (SSE-S3 or SSE-KMS).
  - **Access policies** limiting who and what can read or write logs.

### 3.8 Amazon CloudWatch (Logs and Metrics)

- **CloudWatch Logs:**
  - Receives log streams from the Agent running on the EC2 host.
  - Organizes logs into **log groups** (e.g., `/awide/platform`, `/awide/host`, `/awide/audit`).
  - Provides log retention policies and search/filter capability.
- **CloudWatch Metrics:**
  - Receives host metrics (CPU, memory, disk, network) and optionally application metrics.
  - Used for alarms, dashboards, and autoscaling signals (if auto-scaling is configured).
- **Metrics and alarms examples:**
  - High CPU utilization on the EC2 host.
  - Disk space usage for containers.
  - Error rate spikes in logs (via metric filters).

### 3.9 Kinesis Data Firehose

- **Purpose:** Stream logs from CloudWatch Logs to the S3 logs bucket.
- **Flow:**
  1. Agent sends logs to **CloudWatch Logs**.
  2. CloudWatch Logs subscription filter forwards selected log events to **Kinesis Data Firehose**.
  3. Firehose batches, transforms (optional), and delivers logs to the **S3 logs bucket**.
- **Benefits:**
  - Near real-time ingestion into S3 at scale.
  - Automatic buffering and backpressure handling.
  - Optional transformation using Lambda (e.g., JSON normalization, redaction).

### 3.10 Amazon RDS for PostgreSQL

- **Purpose:** Durable relational data store for the Awide platform.
- **Connectivity:**
  - Accessible from Awide application containers via standard PostgreSQL (`SQL`) connections.
  - Typically deployed into **private subnets** within the same VPC for low-latency access.
- **Configuration considerations:**
  - High availability (Multi-AZ) for production.
  - Storage size and IOPS according to expected workload.
  - Automated backups and point-in-time recovery.
  - Encryption at rest and in transit.

### 3.11 IAM and IAM Roles

- **IAM Users / Federated Identities:**
  - Administrators and operators manage the stack using IAM users or federated SSO roles.
- **EC2 Instance Role (Instance Profile):**
  - Grants the Awide EC2 host permissions to:
    - Write to CloudWatch Logs and publish metrics.
    - Write to the S3 logs bucket.
    - Put records into Firehose (if the host participates directly).
    - Read/write to RDS only if using IAM authentication (optional, depends on configuration).
- **Service Roles:**
  - **Kinesis Data Firehose role** to read from CloudWatch Logs and write to S3.
  - **RDS service role** for monitoring and integration with CloudWatch.
- **Principles:**
  - Use **least privilege** for every role.
  - Prefer **managed policies** where available, with additional inline constraints as needed.

---

## 4. Data Flows

### 4.1 Software Update Flow

1. The **Update Agent** on the Awide EC2 instance periodically connects to **awidelabs.io** over HTTPS.
2. The agent retrieves release metadata (current versions, changelogs, required migrations).
3. When a newer compatible version is available, the Update Agent pulls corresponding container images from **Private Docker Repository **.
4. The Update Agent orchestrates container deployment (pull image, stop old container, start new container, run health checks).
5. All update actions are logged locally and forwarded to CloudWatch and/or S3.

### 4.2 Application Runtime and Database Flow

1. **Application containers** run on the Awide EC2 host.
2. The containers connect to **RDS PostgreSQL** using SQL, typically over a VPC-internal TCP connection on port 5432.
3. Authentication is handled via database credentials stored securely (e.g., in AWS Secrets Manager or SSM Parameter Store – depending on environment configuration).
4. Application reads/writes data in PostgreSQL, which persists to durable storage.

### 4.3 Logging and Metrics Flow

1. Application containers and the host generate logs and metrics.
2. The **Agent** collects:
   - Container logs from stdout/stderr or log files.
   - Host logs (syslog, application services).
   - Metrics from OS and container runtime.
3. The Agent sends:
   - Logs to **CloudWatch Logs**.
   - Metrics to **CloudWatch Metrics**.
   - Optionally, logs directly to the **S3 logs bucket**.
4. **CloudWatch Logs** can be configured with **subscription filters** that send specific log streams to **Kinesis Data Firehose**.
5. **Kinesis Data Firehose** delivers batched log data to the **S3 logs bucket**, using predefined prefixes and compression settings.
6. Long-term analytics and compliance retrieval are performed directly from S3.

### 4.4 IAM and Security Flow

1. IAM roles and policies define what each component can access.
2. The **EC2 instance role** is attached to the Awide instance via an instance profile.
3. When the EC2 host calls AWS APIs (e.g., `PutLogEvents`, `PutMetricData`, `PutObject`), AWS Security Token Service (STS) issues temporary credentials for the role.
4. AWS services (CloudWatch, Firehose, RDS) also assume their own service-linked or customer-managed roles as required.

---

## 5. Network and Security Architecture

### 5.1 Network Segmentation

- Deploy the Awide EC2 instance and RDS database in **private subnets** to avoid direct inbound access from the internet.
- If the Awide platform needs outbound internet access (for updates, Private Docker Repository , and awidelabs.io):
  - Use a **NAT gateway** in a public subnet.
  - Route outbound traffic from private subnets to the NAT gateway.
- For environments requiring strict egress control:
  - Use **VPC endpoints** for S3, CloudWatch Logs, and Kinesis Firehose.
  - Restrict outbound internet access only to required domains/IP ranges via proxies or egress filters.

### 5.2 Security Groups

Create security groups for each major component:

- **Awide EC2 security group:**
  - Inbound:
    - Administrative SSH or SSM Session Manager (if allowed) from management IP ranges.
    - Application ports from internal clients, load balancers, or bastion hosts.
  - Outbound:
    - To RDS PostgreSQL port.
    - To S3, CloudWatch, Firehose, and awidelabs.io/Private Docker Repository  (either via NAT or endpoints).

- **RDS PostgreSQL security group:**
  - Inbound:
    - PostgreSQL port (default 5432) from the Awide EC2 security group only.
  - Outbound:
    - Default for RDS (no external dependencies beyond VPC and monitoring).

- **Management / bastion / jump host security group (if used):**
  - Controls privileged access to the EC2 host.

### 5.3 Encryption

- **Data in transit:**
  - Use TLS for all connections to awidelabs.io and Private Docker Repository .
  - Enable **SSL/TLS** for PostgreSQL connections between Awide containers and RDS.
  - Use HTTPS for S3 and AWS API calls.

- **Data at rest:**
  - Enable EBS volume encryption for the Awide EC2 instance.
  - Use encrypted RDS instances (KMS-managed keys).
  - Enable server-side encryption for the S3 logs bucket.

### 5.4 Access Management and Least Privilege

- Restrict console and CLI access to AWS resources to a small set of IAM roles or groups.
- Use role-based access control (RBAC) and enforced MFA for administrators.
- Define separate roles for:
  - **Awide host EC2 role** (logging, metrics, S3 access).
  - **Firehose delivery role**.
  - **Ops/Support roles** with read-only access to logs and metrics.
- Use IAM policy conditions to restrict actions by:
  - Source VPC or source IP.
  - Specific S3 prefixes.
  - CloudWatch log groups.

### 5.5 Audit and Compliance

- Ensure **CloudTrail** is enabled for the AWS account and writing to a separate, secured log bucket.
- Consider additional log forwarding from S3 or CloudWatch to a central SIEM via Kinesis, Lambda, or third-party tools.

---

## 6. Deployment Model and Lifecycle

### 6.1 Initial Deployment

1. **Subscribe to Awide AMI** in AWS Marketplace.
2. In the target AWS account and Region:
   - Ensure a suitable **VPC** and **subnets** exist.
   - Create or identify the **RDS PostgreSQL instance**.
   - Create an **S3 logs bucket** with appropriate policies.
   - Configure **CloudWatch log groups** and retention.
   - Create an optional **Kinesis Data Firehose** delivery stream to S3.
3. Create an **IAM role** for the Awide EC2 instance with minimum required permissions.
4. Launch the **Awide EC2 instance** from the Marketplace AMI:
   - Select appropriate instance type (CPU, memory) based on expected load.
   - Attach the instance role.
   - Place instance into private subnets.
5. Configure **security groups** for EC2 and RDS.
6. Configure bootstrap parameters for the Awide platform (e.g., DB connection, license, environment settings).

### 6.2 Update and Patch Management

- **Application updates** are handled primarily by the **Update Agent** via:
  - Fetching new container images from Private Docker Repository .
  - Coordinating in-place updates with minimal downtime.
- **AMI / OS updates:**
  - Periodically, new AMI versions are made available via AWS Marketplace.
  - Upgrade strategies can include:
    - Rolling replacement of EC2 instances using newer AMIs.
    - Blue/green deployments across Auto Scaling Groups.
- **Security patches:**
  - Critical patches may require accelerating AMI or container updates.
  - Use CloudWatch Events / EventBridge or vendor notifications as triggers.

### 6.4 Backup and Recovery

- **RDS:**
  - Enable automated backups and point-in-time recovery.
  - Periodically test restore procedures.
- **S3 logs bucket:**
  - Configure lifecycle policies and, if necessary, cross-region replication.
- **Configuration and state on EC2:**
  - Prefer storing critical configuration in external systems (e.g., RDS, Secrets Manager, S3 configuration bucket) rather than solely on ephemeral storage.
  - Use infrastructure-as-code (e.g., CloudFormation/Terraform) to recreate infrastructure.

---

## 7. Observability and Operations

### 7.1 Monitoring

- **CloudWatch metrics dashboards** for:
  - EC2 instance health (CPU, memory via custom metrics, disk).
  - RDS metrics (CPU, connections, latency, storage, replication lag).
  - Firehose throughput and failure counts.
- **Alarms:**
  - EC2: High CPU, low disk, failed status checks.
  - RDS: High CPU, low free storage, failover events.
  - Logs: Error rate thresholds using metric filters.

### 7.2 Logging

- Standardize log groups and S3 prefixes:
  - CloudWatch log groups such as:
    - `/awide/platform/app`
    - `/awide/platform/host`
    - `/awide/platform/audit`
  - S3 prefixes such as:
    - `logs/app/year=YYYY/month=MM/day=DD/`
    - `logs/host/year=YYYY/month=MM/day=DD/`
- Ensure log retention policies match compliance requirements.

### 7.3 Troubleshooting Workflows

- **Container / application issues:**
  - Inspect CloudWatch Logs for the relevant log groups.
  - Use instance-level access (SSH or SSM) to inspect container status if necessary.
- **Database issues:**
  - Check RDS performance insights and CloudWatch metrics.
  - Examine application logs for SQL timeout or connection errors.
- **Update failures:**
  - Review Update Agent logs in CloudWatch and/or S3.
  - Confirm network connectivity to awidelabs.io and Private Docker Repository .

---

## 8. Security Best Practices

- Run the Awide EC2 instance in **private subnets**; avoid direct public IP when possible.
- Use **SSM Session Manager** instead of SSH for administration where feasible.
- Ensure **RDS** is not publicly accessible.
- Enforce **TLS** everywhere (database, S3, AWS APIs, external endpoints).
- Use **AWS KMS** for encryption keys and manage key policies carefully.
- Restrict S3 bucket access using bucket policies and IAM conditions (e.g., `aws:SourceVpc`, `aws:PrincipalArn`).
- Regularly review IAM policies and CloudTrail logs for anomalous access patterns.
- Integrate Awide logs with centralized SIEM or security analytics tools as required.

---

## 9. Cost Considerations

Key cost drivers:

- **EC2 instance(s):** instance type, count, and uptime.
- **RDS PostgreSQL:** instance class, storage type/size, Multi-AZ.
- **S3 logs bucket:** storage volume, lifecycle settings, retrieval patterns.
- **CloudWatch Logs and Metrics:** ingest volume, retention duration, custom metrics.
- **Kinesis Data Firehose:** data volume processed and delivered.

Cost-optimization measures:

- Use right-sized EC2 and RDS instances and consider Savings Plans/Reserved Instances for steady workloads.
- Tune CloudWatch log retention and S3 lifecycle policies.
- Filter logs sent to Firehose/S3 to only what is required for compliance and troubleshooting.

---

## 10. Responsibilities Summary

- **Vendor (Awide):**
  - Maintain and update the Marketplace AMI and container images.
  - Provide release metadata and update mechanisms via awidelabs.io and Private Docker Repository .

- **Customer (AWS Account Owner):**
  - Manage the AWS environment (VPC, subnets, security groups, IAM, S3, RDS, Firehose, CloudWatch).
  - Ensure security, compliance, backups, monitoring, and incident response.
  - Operate and scale the deployment according to workload needs.

---

## 11. Appendix – Checklist

Use the checklist below when standing up or reviewing an Awide platform deployment:

- [ ] Subscribed to Awide AMI in AWS Marketplace.
- [ ] VPC and subnets created (private subnets for EC2 and RDS).
- [ ] Internet egress (NAT / proxy) configured for updates and container pulls.
- [ ] Security groups configured for EC2 and RDS (least privilege).
- [ ] EC2 instance role created with S3, CloudWatch, and Firehose permissions.
- [ ] RDS PostgreSQL instance created, encrypted, and placed in private subnets.
- [ ] S3 logs bucket created with encryption, lifecycle, and restricted access.
- [ ] CloudWatch log groups created and retention policies set.
- [ ] Kinesis Data Firehose stream configured to deliver logs from CloudWatch to S3.
- [ ] CloudWatch dashboards and alarms configured for EC2, RDS, and logs.
- [ ] Backup and recovery strategy documented and tested.
- [ ] Security review completed (IAM, encryption, network, logging, auditing).
