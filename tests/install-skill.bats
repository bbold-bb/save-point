#!/usr/bin/env bats

load helpers

setup() {
  setup_home
  export SKILLS_HOME_CLAUDE="$BATS_TEST_TMPDIR/claude-skills" SKILLS_HOME_AGENTS="$BATS_TEST_TMPDIR/agents-skills"
}

@test "creates both links pointing at the kit's skill" {
  run /bin/bash "$KIT/bin/install-skill.sh"
  [ "$status" -eq 0 ]
  [ -L "$SKILLS_HOME_CLAUDE/org-backups" ]
  [ -L "$SKILLS_HOME_AGENTS/org-backups" ]
  [ "$(readlink "$SKILLS_HOME_CLAUDE/org-backups")" = "$KIT/skill/org-backups" ]
  [ "$(readlink "$SKILLS_HOME_AGENTS/org-backups")" = "$KIT/skill/org-backups" ]
  [ -f "$SKILLS_HOME_CLAUDE/org-backups/SKILL.md" ]
}

@test "replaces an older link, and running twice is fine" {
  mkdir -p "$SKILLS_HOME_CLAUDE" "$BATS_TEST_TMPDIR/old-kit/skill/org-backups"
  ln -s "$BATS_TEST_TMPDIR/old-kit/skill/org-backups" "$SKILLS_HOME_CLAUDE/org-backups"
  run /bin/bash "$KIT/bin/install-skill.sh"
  [ "$status" -eq 0 ]
  [ "$(readlink "$SKILLS_HOME_CLAUDE/org-backups")" = "$KIT/skill/org-backups" ]
  run /bin/bash "$KIT/bin/install-skill.sh"
  [ "$status" -eq 0 ]
}

@test "a real folder at the target is left alone and reported; the other place still gets its link" {
  mkdir -p "$SKILLS_HOME_CLAUDE/org-backups"; echo mine > "$SKILLS_HOME_CLAUDE/org-backups/SKILL.md"
  run /bin/bash "$KIT/bin/install-skill.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"$SKILLS_HOME_CLAUDE/org-backups"*"left alone"* ]] || false
  [ "$(cat "$SKILLS_HOME_CLAUDE/org-backups/SKILL.md")" = mine ]
  [ -L "$SKILLS_HOME_AGENTS/org-backups" ]
}

@test "the skill has the frontmatter both agents read, and no em dashes anywhere in the kit's docs" {
  head -1 "$KIT/skill/org-backups/SKILL.md" | grep -qx -- '---'
  grep -qx 'name: org-backups' "$KIT/skill/org-backups/SKILL.md"
  grep -q '^description: ' "$KIT/skill/org-backups/SKILL.md"
  desc="$(sed -n 's/^description: //p' "$KIT/skill/org-backups/SKILL.md")"
  [ "${#desc}" -le 1024 ]
  for f in "$KIT/README.md" "$KIT"/skill/org-backups/*.md "$KIT"/skill/org-backups/references/*.md; do
    if grep -q $'\xe2\x80\x94' "$f"; then echo "em dash in $f"; false; fi
  done
  for r in setup restore troubleshooting what-is-backed-up; do [ -f "$KIT/skill/org-backups/references/$r.md" ]; done
}

@test "every script the skill names exists in bin/" {
  for s in $(grep -oh '[a-z-]*\.sh' "$KIT"/skill/org-backups/SKILL.md "$KIT"/skill/org-backups/references/*.md | sort -u); do
    [ -x "$KIT/bin/$s" ] || { echo "missing: $s"; false; }
  done
}
