# Analysis Archive

**Purpose**: Historical and superseded analysis documents preserved for reference.

**Status**: These documents represent earlier investigation phases and have been superseded by newer, better-documented analysis.

---

## Contents by Category

### SH2 Analysis (Superseded by recent complete analysis)
- `SH2_CODE_HUNT.md` - Early code discovery methodology
- `SH2_CODE_BOUNDARIES.md` - Initial code boundary identification
- `SH2_CONVERSION_PLAN.md` - SH2 assembly conversion planning
- `SH2_CONVERSION_STATUS.md` - Early conversion progress tracking
- `SLAVE_TEST_STATUS.md` - Old Slave processor testing notes
- `SLAVE_VERIFICATION_RESULTS.md` - Early Slave verification attempts

**Why archived**: Superseded by [SH2_ANALYSIS_COMPLETE.md](../sh2-analysis/SH2_ANALYSIS_COMPLETE.md), [SH2_3D_PIPELINE_ARCHITECTURE.md](../sh2-analysis/SH2_3D_PIPELINE_ARCHITECTURE.md), and other comprehensive SH2 analysis

### Debugger Investigation (Superseded by PDCORE design)
- `R2_DEBUGGER_RESULTS.md` - R2 debugger measurement results
- `R2_DEBUGGER_TRACE_PLAN.md` - R2 tracing methodology
- `R2_INVESTIGATION_SUMMARY.md` - R2 investigation findings
- `R2_TECHNICAL_ASSESSMENT.md` - R2 technical analysis
- `GDB_PORT_REFERENCE.md` - GDB port reference
- `GDB_TROUBLESHOOTING_COMMANDS.md` - GDB troubleshooting guide
- `GENS_GDB_ISSUES.md` - Gens emulator GDB issues
- `PDB_DEBUGGER_USAGE.md` - PDB debugger usage guide

**Why archived**: Superseded by modern PDCORE design in [debugger-design/](../debugger-design/):
- [PDCORE_MASTER_PLAN.md](../debugger-design/PDCORE_MASTER_PLAN.md)
- [PDCORE_MVP1_ROADMAP.md](../debugger-design/PDCORE_MVP1_ROADMAP.md)
- [PDCORE_API_DESIGN.md](../debugger-design/PDCORE_API_DESIGN.md)

### 68K Analysis Planning (Superseded by complete analysis)
- `68K_PRIORITY_8_PLAN.md` - Original Priority 8 investigation plan
- `68K_PRIORITY_8_ENTRY_TYPES.md` - Early function type analysis
- `68K_PRIORITY_8_D1D4_CALLER_ANALYSIS.md` - Initial caller analysis
- `ANNOTATION_GUIDE.md` - Early annotation methodology
- `ANNOTATION_TASKS.md` - Old annotation work tracking

**Why archived**: Superseded by comprehensive 68K analysis in [68k-reverse-engineering/](../68k-reverse-engineering/):
- [68K_FUNCTION_REFERENCE.md](../68K_FUNCTION_REFERENCE.md)
- [68K_FUNCTION_INVENTORY.md](../68k-reverse-engineering/68K_FUNCTION_INVENTORY.md)
- Game logic modules (complete analysis of all 8 game systems)

### Session & Status Tracking (Temporary work documents)
- `ANALYSIS_REVISION_2026-01-20.md` - Analysis methodology revision notes
- `BASELINE_VERIFIED.md` - Baseline ROM verification status
- `DOCUMENTATION_REVISION_SUMMARY.md` - Documentation structure update notes
- `SIMPLE_COMM_TEST_PLAN.md` - Early COMM test planning
- `WORK_DISTRIBUTION_PLAN.md` - Session work breakdown
- `WORK_DISTRIBUTION_SESSION_SUMMARY.md` - Session summary report

**Why archived**: These were temporary work-tracking documents from development sessions and are no longer needed for reference

---

## Accessing Archived Documents

These documents are preserved in git history and can be accessed with:

```bash
git log --all --oneline -- analysis/_archive/
git show <commit>:analysis/_archive/<filename>
```

---

## Current Active Documentation

For current analysis, see the parent `README.md` and active subdirectories:
- [architecture/](../architecture/) - ROM structure, memory maps, V-INT handlers, game logic
- [debugger-design/](../debugger-design/) - PDCORE debugger design (active project)
- [sh2-analysis/](../sh2-analysis/) - SH2 3D engine and processor analysis
- [68k-reverse-engineering/](../68k-reverse-engineering/) - 68K code analysis
- [optimization/](../optimization/) - Performance optimization research
- [profiling/](../profiling/) - Cycle profiling and performance measurement

---

**Last Updated**: 2026-01-21
**Archival Date**: 2026-01-21 (Documentation streamlining)
