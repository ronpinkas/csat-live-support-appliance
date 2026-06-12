#!/usr/bin/env bash
#
# unlock-my-ip.sh — Update the appliance "ssh-self" security-group rule to
#                   allow SSH from the current public IP.
#
# Same pattern as hy-rag/unlock-my-ip.sh (the standing workflow when Ron's
# public IP rotates), pointed at the appliance EC2's security group.
#
# Usage: ./unlock-my-ip.sh [--dry-run]
#
set -euo pipefail

# ── Constants ──────────────────────────────────────────────────────────────────
SSH_SG="sg-0ed0ae46fa44494c7" # appliance (44.198.69.248, i-09b9d4f9d94ce05bf)
RULE_DESC="ssh-self"
REGION="us-east-1"
SETAWS="$HOME/git/hy-rag/setaws.sh"

DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    *) echo "Unknown option: $arg"; echo "Usage: $0 [--dry-run]"; exit 1 ;;
  esac
done

log() { echo "[$(date '+%H:%M:%S')] $*"; }
err() { echo "[$(date '+%H:%M:%S')] ERROR: $*" >&2; }

# ── Preflight: AWS access (auto-source setaws.sh if needed) ──────────────────
if ! aws sts get-caller-identity --region "$REGION" &>/dev/null; then
  if [[ -f "$SETAWS" ]]; then
    log "AWS not configured — sourcing setaws.sh"
    # shellcheck disable=SC1091
    source "$SETAWS"
    if ! aws sts get-caller-identity --region "$REGION" &>/dev/null; then
      err "AWS access still failing after sourcing setaws.sh"
      exit 1
    fi
    log "AWS access verified (via setaws.sh)"
  else
    err "AWS CLI not configured and setaws.sh not found at $SETAWS"
    exit 1
  fi
else
  log "AWS access verified"
fi

# ── Determine current public IP ──────────────────────────────────────────────
MY_IP=$(curl -4 -s --max-time 5 https://ifconfig.me)
if [[ -z "$MY_IP" ]]; then
  err "Could not determine public IP"
  exit 1
fi
log "Current public IP: $MY_IP"

# ── Check existing rule ───────────────────────────────────────────────────────
CURRENT_RULE_IP=$(aws ec2 describe-security-group-rules \
  --region "$REGION" \
  --filters "Name=group-id,Values=$SSH_SG" \
  --query "SecurityGroupRules[?Description=='$RULE_DESC' && FromPort==\`22\`].CidrIpv4" \
  --output text 2>/dev/null)

if [[ "$CURRENT_RULE_IP" == "${MY_IP}/32" ]]; then
  log "$RULE_DESC rule already has $MY_IP — nothing to do"
  exit 0
else
  log "$RULE_DESC rule has ${CURRENT_RULE_IP:-<none>}, updating to $MY_IP"
fi

# ── Update the rule ──────────────────────────────────────────────────────────
if ! $DRY_RUN; then
  OLD_RULE_ID=$(aws ec2 describe-security-group-rules \
    --region "$REGION" \
    --filters "Name=group-id,Values=$SSH_SG" \
    --query "SecurityGroupRules[?Description=='$RULE_DESC' && FromPort==\`22\`].SecurityGroupRuleId" \
    --output text 2>/dev/null)
  if [[ -n "$OLD_RULE_ID" && "$OLD_RULE_ID" != "None" ]]; then
    aws ec2 revoke-security-group-ingress \
      --region "$REGION" \
      --group-id "$SSH_SG" \
      --security-group-rule-ids "$OLD_RULE_ID" >/dev/null
    log "Revoked old rule: $OLD_RULE_ID ($CURRENT_RULE_IP)"
  else
    log "No existing $RULE_DESC rule found — adding new"
  fi
  aws ec2 authorize-security-group-ingress \
    --region "$REGION" \
    --group-id "$SSH_SG" \
    --ip-permissions "IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=${MY_IP}/32,Description=$RULE_DESC}]" >/dev/null
  log "Added $RULE_DESC rule for $MY_IP — SSH unlocked"
else
  echo "  [dry-run] would update $RULE_DESC: ${CURRENT_RULE_IP:-<none>} → ${MY_IP}/32"
fi
