#!/bin/bash

# Script to copy existing documentation files to new locations
# Run from the docs directory

echo "Copying existing documentation to new structure..."

# Copy to hardware/
cp proxmox-setup.md hardware/proxmox.md
cp truenas.md hardware/truenas.md
cp network.md hardware/network.md

# Copy to setup/
cp ansible.md setup/ansible.md
cp custom-images.md setup/custom-images.md
cp bare-metal.md setup/bare-metal.md

# Copy to cluster-core/
cp argocd.md cluster-core/argocd.md
cp traefik.md cluster-core/traefik.md
cp metallb.md cluster-core/metallb.md
cp cert-manager.md cluster-core/cert-manager.md
cp authentik.md cluster-core/authentik.md
cp vault.md cluster-core/vault.md
cp longhorn.md cluster-core/longhorn.md
cp monitoring.md cluster-core/monitoring.md

# Copy to platform/
cp postgres-cnpg.md platform/postgres-cnpg.md
cp postgres-zalando.md platform/postgres-zalando.md
cp secrets-csi.md platform/secrets-csi.md
cp external-secrets.md platform/external-secrets.md

# Copy to apps/
cp plex.md apps/plex.md
cp adguard.md apps/adguard.md
cp uptime-kuma.md apps/uptime-kuma.md
cp securitycam.md apps/securitycam.md
cp rails-app.md apps/rails-app.md
cp vpn.md apps/vpn.md

echo "Done! Files copied to new locations."
echo ""
echo "Note: Original files are preserved. You can delete them after verifying the new structure works."
echo ""
echo "Next steps:"
echo "1. Review the copied files"
echo "2. Test with: mkdocs serve"
echo "3. Update internal links if needed"
echo "4. Remove original files when ready"
