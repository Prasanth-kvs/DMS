# Scalable Disk Monitoring — Case Study Submission

A design and working implementation for monitoring disk utilization across every VM in a
multi-account **AWS** organization, built on **Ansible** and adding CloudWatch only where
it provides a clear benefit (continuous collection and alerting).

**Full documentation: [disk-monitoring/README.md](disk-monitoring/README.md)**

| Deliverable | Where |
|---|---|
| High-level architecture diagram | [Architecture](disk-monitoring/README.md#architecture) |
| Ansible playbooks and roles | [disk-monitoring/playbooks](disk-monitoring/playbooks), [disk-monitoring/roles](disk-monitoring/roles) |
| Minimal working demo (fill a disk, watch the alarm fire) | [Minimal working demo](disk-monitoring/README.md#minimal-working-demo) |
| Access management | [Access management](disk-monitoring/README.md#access-management) |
| VM discovery and enrollment | [VM discovery and enrollment](disk-monitoring/README.md#vm-discovery-and-enrollment) |
| Data collection and aggregation | [Data collection](disk-monitoring/README.md#data-collection), [Aggregation and presentation](disk-monitoring/README.md#aggregation-and-presentation) |
| Scalability | [Scalability](disk-monitoring/README.md#scalability) |
| Cost estimate | [Cost](disk-monitoring/README.md#cost-estimate) |
| Testing with one AWS account (test mode) | [Testing in a single AWS account](disk-monitoring/README.md#testing-in-a-single-aws-account) |
| Test results and screenshots | [Testing performed](disk-monitoring/README.md#testing-performed) |
| Cloud plumbing (Terraform + CloudFormation StackSet) | [disk-monitoring/terraform](disk-monitoring/terraform), [disk-monitoring/cloudformation](disk-monitoring/cloudformation) |

**In one line:** Terraform builds the plumbing, Ansible discovers, enrolls and manages
the VMs over SSM (no SSH, no inbound ports), the CloudWatch agent collects continuously,
and one monitoring account alarms on and displays the whole fleet.

**Tested:** live in a **single AWS account** (test mode: 2 EC2 instances, full pipeline,
dashboard and alarms; screenshots in [disk-monitoring/docs/screenshots](disk-monitoring/docs/screenshots)).
The cross-account parts (StackSet, OAM metrics sharing, Organizations discovery, SCP) follow
AWS's documented patterns but were not run live; see
[Not tested live](disk-monitoring/README.md#not-tested-live).
