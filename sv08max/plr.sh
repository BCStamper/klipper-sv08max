#!/bin/sh
# SV08 MAX PLR regeneration — byte-offset seek variant (replaces Sovol's sed pipeline).
# Reads journal from saved_variables (written by [delayed_gcode plr_journal]),
# writes a resumable file to ~/printer_data/gcodes/plr/<last_file>.
python3 - <<'EOF'
import ast, configparser, os, sys

VARS = os.path.expanduser("~/printer_data/config/saved_variables.cfg")
cp = configparser.ConfigParser()
cp.read(VARS)
def var(k):
    return ast.literal_eval(cp.get("Variables", k))

st = var("plr_state")
filepath = var("filepath")
last_file = var("last_file")
if last_file == "default":
    sys.exit("PLR: no interrupted file recorded")

fp = int(st["fp"])
outdir = os.path.expanduser("~/printer_data/gcodes/plr")
os.makedirs(outdir, exist_ok=True)

src = open(filepath, "rb")
head = src.read(fp)
# snap resume point back to a line boundary
resume_off = head.rfind(b"\n") + 1

# scan the consumed part for extrusion mode and last absolute E value
mode, e_last = "M82", None
for line in head.decode("utf-8", "ignore").splitlines():
    s = line.strip().upper()
    if s.startswith("M83"):
        mode = "M83"
    elif s.startswith("M82"):
        mode = "M82"
    if s.startswith(("G1 ", "G0 ")) and " E" in s:
        try:
            e_last = float(s.split(" E")[1].split()[0].rstrip(";"))
        except ValueError:
            pass

out = open(os.path.join(outdir, last_file), "w")
w = out.write
w("; SV08MAX PLR regenerated resume file (offset %d)\n" % resume_off)
w("SET_KINEMATIC_POSITION Z=%s\n" % st["z"])
w("M140 S%s\nM104 S%s\n" % (st["btemp"], st["etemp"]))   # start heating early
w("G91\nG1 Z5 F600\nG90\n")                              # lift off the print
w("G28 X Y\n")                                           # home XY only, Z stays journaled
w("M190 S%s\nM109 S%s\n" % (st["btemp"], st["etemp"]))
w("M106 S%s\n" % st.get("fan", 255))
w("G0 F9000 X%s Y%s\n" % (st["x"], st["y"]))
w("G0 Z%s F600\n" % st["z"])
w("%s\n" % mode)
if mode == "M82" and e_last is not None:
    w("G92 E%s\n" % e_last)
elif mode == "M83":
    w("G92 E0\n")

src.seek(resume_off)
out.write(src.read().decode("utf-8", "ignore"))
out.close()
print("PLR file written: plr/%s (resume offset %d)" % (last_file, resume_off))
EOF
