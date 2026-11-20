#!/bin/bash
# Save Point: installs the org-backups skill for Claude Code and Codex.
#
#   install-skill.sh
#
# Links the kit's skill/org-backups folder into ~/.claude/skills/org-backups (Claude Code) and
# ~/.agents/skills/org-backups (Codex). A link, not a copy, so the skill updates whenever the kit is updated with
# git pull. An older link is replaced. A real folder already at either place is left alone and reported.
# SKILLS_HOME_CLAUDE and SKILLS_HOME_AGENTS change the two places (the tests use them).

set -u
. "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"

SOURCE="$KIT_DIR/skill/org-backups"
[ -f "$SOURCE/SKILL.md" ] || die "The kit's skill is missing: $SOURCE/SKILL.md"

problems=0
for home in "${SKILLS_HOME_CLAUDE:-$HOME/.claude/skills}" "${SKILLS_HOME_AGENTS:-$HOME/.agents/skills}"; do
  target="$home/org-backups"
  mkdir -p "$home"
  if [ -L "$target" ]; then
    if [ "$(readlink "$target")" = "$SOURCE" ]; then echo "Already linked: $target"; continue; fi
    rm -f "$target"
  elif [ -e "$target" ]; then
    echo "$target is a real folder, not a link, so it was left alone. Move it aside and run this again to link the kit's skill."
    problems=1
    continue
  fi
  ln -s "$SOURCE" "$target"
  echo "Linked: $target -> $SOURCE"
done
[ "$problems" -eq 0 ] && echo "Open Claude Code or Codex and say \"set up org backups\"."
exit "$problems"
