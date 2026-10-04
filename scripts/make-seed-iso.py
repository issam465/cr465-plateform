import io
import pathlib
import pycdlib
 
ROOT = pathlib.Path(__file__).resolve().parent.parent
USER_DATA = (ROOT / "cloud-init" / "user-data.yaml").read_bytes()
META_DATA = b"instance-id: cr465-vm-01\nlocal-hostname: cr465-vm\n"
OUTPUT = ROOT / "seed.iso"
 
if b"AAAA_REMPLACER" in USER_DATA:
    raise SystemExit("Erreur : la cle SSH publique n'a pas ete mise dans user-data.yaml")
 
iso = pycdlib.PyCdlib()
iso.new(interchange_level=3, joliet=3, rock_ridge="1.09", vol_ident="cidata")
for name, data in (("user-data", USER_DATA), ("meta-data", META_DATA)):
    short = "/" + name.replace("-", "").upper()[:8] + ".;1"
    iso.add_fp(io.BytesIO(data), len(data), short, rr_name=name, joliet_path="/" + name)
iso.write(str(OUTPUT))
iso.close()
print(f"OK : {OUTPUT} cree")