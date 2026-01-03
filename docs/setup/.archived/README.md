# Archived Files - Content Reorganization

This directory contains backup copies of files that were reorganized on January 2, 2026.

## Files Archived

- `ansible.md` - Content moved to:
  - `setup/node-provisioning.md` (Ansible operations section)
  - `setup/manual-installation.md` (Manual k3s install)
  
- `bare-metal.md` - Content moved to:
  - `setup/node-provisioning.md` (MinIO, backups, hardware configs)
  - `hardware/raspberry-pi.md` (Hardware vendors list)

## Reason for Reorganization

These files had significant content duplication with each other and with `hardware/raspberry-pi.md`. The reorganization created clear boundaries:

- **Hardware guide** = Physical setup only
- **Node provisioning** = Software provisioning with Ansible
- **Manual installation** = Manual k3s setup (without Ansible)

See `docs/CONTENT_REORGANIZATION_PROPOSAL.md` for full details.
