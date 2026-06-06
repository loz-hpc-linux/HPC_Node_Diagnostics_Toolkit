# HPC Node Diagnostics Toolkit

A collection of Bash utilities designed to assist with diagnosing and triaging node issues in large-scale Linux HPC clusters.

The toolkit focuses on rapid infrastructure investigation by automating common operational tasks such as:

- log analysis
- node classification
- scheduler state inspection
- hardware information gathering
- network diagnostics

These tools were developed to streamline troubleshooting workflows across distributed HPC environments where investigations often span multiple operational layers including compute, management, scheduling, and networking services.

Developed while operating large-scale Cray EX series clusters containing thousands of compute nodes.

The scripts are designed to be lightweight, composable, and easily executed from standard Linux environments used to operate HPC clusters.

---

## Features

- Remote CPU and hardware identification
- Node connectivity and availability monitoring
- Automated log scanning across distributed system components
- PBS scheduler state inspection and parsing
- Cluster sweep classification for operational triage
- Environment setup for structured debugging sessions
- Fabric diagnostics for Slingshot link stability
- Memory ECC health inspection via ras-mc-ctl

---

## Purpose

These tools were created to improve the efficiency of diagnosing infrastructure issues in distributed Linux HPC environments.

By automating repetitive investigative tasks, the toolkit helps operators:

- identify faults faster
- correlate failures across infrastructure layers
- reduce manual log inspection
- standardise operational troubleshooting workflows

---

## Example Workflow

The toolkit is designed to support a **structured investigation workflow** commonly used during HPC node triage and incident response.

Rather than running scripts independently, operators typically follow a sequence of investigation stages.

The workflow below illustrates a typical diagnostic path.

---

### 1. Initialise Investigation Environment

Before beginning diagnostics, initialise the investigation environment.

source setup_env.sh

This resolves infrastructure metadata and prepares the shell session with consistent variables used by other scripts.

The script automatically determines:

- node xname
- BMC address
- slot and chassis location
- sibling nodes on the same blade

These environment variables allow subsequent scripts to operate without repeatedly resolving infrastructure relationships.

---

### 2. Inspect Scheduler and Platform State

Check whether the node appears healthy from both the scheduler and system management perspective.

./status_checker.sh $SLOT

This correlates:

- PBS scheduler state  
- SAT platform management state  

Typical issues identified at this stage include:

- nodes marked offline or drained
- configuration mismatches
- nodes failing to boot
- discrepancies between scheduler and platform views

---

### 3. Perform Slot-Level Log Triage

If infrastructure issues are suspected, logs from both BMC sides of the slot are scanned.

./log_scan.sh $SLOT

The script performs rapid keyword searches across:

/var/log/messages  
/var/log/n*/current  

Common failure indicators include:

- hardware faults
- power events
- PCIe errors
- HSN fabric issues
- squashfs filesystem errors
- machine check exceptions (MCE / MCA)

This stage provides a quick overview of potential failure signals across all nodes in the slot.

---

### 4. Investigate Specific Log Events

Once a potential failure indicator is identified, deeper investigation can be performed using targeted log searches.

./log_search.sh -p "lmon link down" -A 50 -B 50

This retrieves the most recent matching log entry and surrounding context, helping operators understand the sequence of events that led to the failure.

Typical investigations include:

- power sequencing failures
- sensor alerts
- hardware telemetry errors
- node boot failures

---

### 5. Verify Hardware Characteristics

Hardware configuration can be validated during troubleshooting.

./cpu_type.sh $XNAME

This identifies the CPU generation and processor details of the compute node, which is useful when diagnosing heterogeneous cluster environments.

---

### 6. Check Memory Health

Memory reliability can be assessed by querying ECC error counters.

./memory_error_check.sh $XNAME

The script retrieves per-channel error counts and evaluates results against cluster health thresholds used by Node Health Check (NHC) policies.

---

### 7. Investigate Fabric Connectivity

If network instability is suspected, investigate Slingshot fabric ports associated with the node.

./link_flap_check.sh $XNAME

The script maps compute nodes to their corresponding switch ports and retrieves link flap information from fabric management services.

Typical use cases include diagnosing:

- HSN link instability
- intermittent connectivity issues
- network congestion symptoms

---

### 8. Monitor Node Recovery

When nodes are rebooting or returning from maintenance, their availability can be monitored.

./ping_nodes.sh $XNAME

The script continuously checks connectivity for all nodes within a blade and reports when they become reachable.

---

### 9. Run Cluster Sweeps

For broader cluster health monitoring, cluster sweep utilities can be executed.

./run_sweeps.sh

This runs multiple operational checks including:

- PBS node sweeps
- node classification
- system-level infrastructure checks

The output provides a consolidated overview of cluster state and can be used for operational reporting or incident triage.

---

## Requirements

• Linux environment  
• SSH access to compute nodes  
• jq (for PBS JSON parsing)  
• Access to cluster management utilities where applicable

---

## Scripts

### cpu_type.sh
Queries a remote compute node to identify the installed CPU architecture and processor details. 
The script connects to the specified node via SSH, runs lscpu, and extracts key information including model name, CPU family, and model number.
Using these values, the script performs simple architecture detection logic to determine whether the node is running AMD EPYC Milan or Genoa processors, which are common CPU generations in modern HPC platforms. 
The output provides a quick hardware verification check that can be useful when investigating node behaviour, validating hardware configuration, or confirming CPU generation during diagnostics.
Typical use cases include hardware verification, architecture-aware troubleshooting, and confirming node CPU types when investigating scheduler allocations or platform behaviour across heterogeneous HPC clusters.

---

### functions.sh

Shared utility library used by the HPC diagnostics toolkit to provide common helper functions and reduce code duplication across scripts.
The file contains reusable functions for input validation, identifier parsing, system information lookups, data formatting, and workflow automation commonly required during Linux and HPC administration tasks.

Key capabilities include:
* Validating and parsing structured system identifiers.
* Translating between different node naming conventions.
* Gathering node and system metadata.
* Identifying hardware architecture characteristics for targeted analysis.
* Providing helper functions for infrastructure and diagnostics workflows.
* Simplifying interaction with system management and monitoring interfaces.
* Supporting automated reporting, health checks, and troubleshooting activities.

By centralising frequently used functions into a single library, the toolkit maintains consistent behaviour across scripts, improves maintainability, and reduces duplication of operational logic.
Typical use cases include system health validation, diagnostics automation, infrastructure reporting, workflow standardisation, and Linux administration tasks within large-scale HPC environments.



---

### link_flap_check.sh
Queries Slingshot fabric management data to identify the network switch ports associated with one or more compute node xnames, then retrieves link flap information for those ports. 
The script looks up conn_port values in fabric_template.json via the Slingshot Fabric Manager (FMN) and runs diagnostic commands such as show-flaps for each discovered port.
It accepts single xnames as well as comma-separated or space-separated node lists, automatically removes duplicate entries, and resolves the relevant port mappings without leaving files behind after execution. 
The script prefers an existing fmnpod helper where available, but can also fall back to kubectl exec into a running slingshot-fabric-manager pod if direct FMN access is not present.
Typical use cases include investigating HSN link instability, checking for fabric flap history on ports serving specific compute nodes, and correlating node-level network issues with switch-port behaviour in Slingshot-based HPC environments.

---

### log_scan.sh
Runs a standard set of targeted log searches across both BMC sides of a slot (<SLOT>b0 and <SLOT>b1) over SSH to speed up first-pass HPC triage. 
The script resolves related xname/NID information from /etc/cray/nidX, prints useful slot context (xnames, BMC, chassis), and scans both /var/log/n*/current and /var/log/messages for common failure indicators, 
such as failed, error, fault, power, HSN, PCIe, MCA, MCE, squashfs, and node power state markers (type Off / type On). 
Results are grouped by log type and slot side, with recent matches shown via tail, making it useful for quickly spotting hardware, boot, fabric, filesystem, and power-related issues across an entire slot.

---

### log_search.sh
Searches remote Cray BMC logs for a user-defined pattern and returns contextual output around the most recent match. 
The script connects to the target BMC via SSH, scans /var/log/messages and /var/log/n*/current, and identifies the last occurrence of the search pattern across all logs. 
It then prints configurable lines of context before and after the match, helping operators quickly understand the surrounding events during hardware or node fault investigation.
The script supports extended regular expressions, prompts for a pattern if one is not supplied, and encodes the search pattern to safely execute against minimal remote shells 
(including BusyBox environments commonly found on BMC systems). It also performs environment checks to ensure the correct BMC target is set and automatically handles file discovery across node log paths.
Typical use cases include diagnosing power faults, sensor errors, node crashes, hardware telemetry events, and boot failures by quickly locating the most recent relevant log entry and its surrounding context.

---

### memory_error_check.sh
Queries compute nodes for memory ECC error statistics using ras-mc-ctl and reports per-channel and per-node error counts. 
The script connects to one or more nodes via SSH, retrieves hardware error counters, and summarises correctable errors (CE) and uncorrectable errors (UE) across all memory channels.
Results are displayed in a structured table showing individual memory channel statistics alongside total CE and UE counts for the node.
The script also evaluates the results against the current Node Health Check (NHC) policy used in the environment, indicating whether the node would pass or fail health checks based on configured thresholds.
By default, only channels with non-zero error counts are displayed, though an option is available to show all memory channels including those with zero errors.
Typical use cases include hardware health diagnostics, investigating node instability, identifying failing DIMMs or memory channels, and verifying whether memory error rates exceed operational thresholds that would trigger node offlining within the cluster scheduler.

---

### node_sweep_report.sh
Automates first-pass triage of compute nodes by running a cluster sweep and classifying nodes based on existing incident or ticket status. 
The script executes sweepPBSNodes.sh, parses the resulting node summary, and separates nodes into existing issues and new faults requiring investigation.
Nodes are classified by inspecting scheduler comments associated with each node:
Existing — nodes already linked to incident tickets
New — nodes without tickets or marked with NHC or communication closed states
The script preserves the original Node Summary output from the sweep while producing a simplified classification that can be quickly shared in Slack, operational handovers, or Jira incident updates. Temporary files are created during processing and automatically cleaned up.
Typical use cases include daily node health sweeps, incident triage, identifying newly failing nodes, and preparing operational summaries during HPC cluster support rotations.

---

### pbs.sh
Queries the PBS scheduler to retrieve and display detailed node state and metadata for one or more nodes in the cluster. 
The function connects to the appropriate login node for the target system, executes pbsnodes in JSON mode, and parses the output using jq and awk to produce a clean, tabular summary.
The output includes key infrastructure attributes such as Cray host ID, hostname, xname, switch location, CPU architecture, workload type, node state, scheduler comment, and active jobs. 
If no nodes are specified, the function returns the state of all nodes visible to the scheduler; otherwise it restricts the query to the provided node set.
Typical use cases include inspecting scheduler state during node triage, verifying resource attributes, identifying nodes that are offline or drained, and quickly correlating scheduler metadata with infrastructure issues across large HPC clusters.

---

### ping_nodes.sh
Monitors the network reachability of all compute nodes associated with a blade by repeatedly pinging each node and reporting its online status. 
The script determines the blade layout using the $NODES_XNAME environment variable and automatically selects the correct node pattern for either Windom or Antero blades.
Once the node list is derived from the provided xname, the script continuously checks each node using ICMP ping and prints a live status summary indicating whether nodes are responding. 
The loop continues until all nodes on the blade become reachable, making it useful for tracking node recovery during power operations, boot sequences, or maintenance work.
Typical use cases include monitoring node availability during blade bring-up, verifying cluster recovery after maintenance, and confirming that all nodes within a slot have returned to network reachability.

---

### run_sweeps.sh
Orchestrates a sequence of cluster health checks by executing multiple diagnostic scripts and presenting their output in a structured format. The script acts as a wrapper around several operational tools, running them in order and clearly labelling the output from each stage.
For each task, the script verifies that the target script exists and is executable before running it. Execution results are reported with colour-coded status messages indicating success or failure, making it easier to review results during operational checks or incident triage sessions.
The workflow currently includes:
PBS node sweep to inspect scheduler-visible node health
Node sweep reporting to summarise findings from previous checks
Cray system sweep to examine infrastructure-level node state
This wrapper provides a convenient way to run multiple diagnostics together while maintaining clear separation of their outputs.
Typical use cases include daily cluster health checks, operational monitoring during support rotations, and quickly gathering system status information during incident investigations.

---

### setup_env.sh
Initialises a structured troubleshooting environment for investigating node issues within an HPC cluster. 
The script prompts the operator for a ticket identifier and node NID, then resolves related infrastructure information such as the node xname, BMC address, slot, chassis, and associated nodes within the same blade.
When sourced into the current shell session, the script exports a set of environment variables that standardise the investigation context and make it easier for other diagnostic scripts to operate without repeatedly resolving infrastructure metadata. 
It also loads shared utility functions, updates the $PATH to include common operational tooling, and optionally applies a custom command prompt to visually indicate an active triage session.
Additional safeguards allow the user to lock the environment variables as readonly to prevent accidental modification during troubleshooting.
Typical use cases include incident response, node triage sessions, infrastructure debugging workflows, and preparing a consistent shell environment for running cluster diagnostic scripts.

---

### status_checker.sh
Checks the operational state of nodes within a specified slot by querying both the PBS scheduler and the SAT (System Admin Toolkit) management interface. 
The script provides a quick infrastructure health snapshot by correlating scheduler node states with the platform management view of the same nodes.
After validating that the required environment variables are set, the script retrieves node information from PBS via the appropriate login node and filters the results for the specified slot. 
It then runs a SAT query to display the system-level status of the corresponding nodes, including attributes such as xname, role, state, network status, boot state, and configuration status.
By presenting scheduler and platform management data together, the script helps operators quickly determine whether nodes are healthy, misconfigured, offline, or failing to boot, and whether discrepancies exist between the scheduler and system management layers.
Typical use cases include slot-level health checks, identifying nodes that are unavailable to the scheduler, verifying system configuration after maintenance, and investigating cases where nodes appear operational but are not marked ready in cluster management tools.

---

## License

MIT
