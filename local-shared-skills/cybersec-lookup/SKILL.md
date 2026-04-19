# cybersec-lookup

Use this skill when a task asks for security scanning, vulnerability lookup, DevSecOps guidance, or cyber-security knowledge lookup.

## Contract

1. Identify the asset, package, workflow, or security question being checked.
2. Prefer local repository evidence first: manifests, lockfiles, CI configuration, scripts, and existing security docs.
3. Use approved lookup tools or primary sources when current vulnerability data is required.
4. Report findings by severity, affected component, evidence, and concrete remediation.
5. Distinguish confirmed issues from hypotheses or missing evidence.

## Safety

- Do not run destructive tests, exploit code, credential dumps, or production-impacting probes without explicit approval.
- Read-only scans and local file inspection do not require user approval.
- Redact secrets and tokens from all output.
