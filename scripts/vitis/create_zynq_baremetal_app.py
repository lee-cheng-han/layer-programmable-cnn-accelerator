import os
import shutil
from pathlib import Path
import vitis

root = Path(os.getcwd())
workspace = root / "build" / "vitis_ws"
xsa_file = root / "build" / "zybo_z7_20_cnn" / "zybo_z7_20_cnn.xsa"

platform_name = "zybo_z7_20_cnn_platform"
app_name = "cnn_baremetal"
domain_name = "standalone_domain"

app_dir = workspace / app_name

print("Workspace:", workspace)
print("XSA:", xsa_file)

if not xsa_file.exists():
    raise FileNotFoundError(f"Missing XSA: {xsa_file}")

if workspace.exists():
    print(f"Removing old Vitis workspace: {workspace}")
    shutil.rmtree(workspace)

workspace.mkdir(parents=True, exist_ok=True)

client = vitis.create_client()
client.set_workspace(path=str(workspace))

platform = client.create_platform_component(
    name=platform_name,
    hw_design=str(xsa_file),
    os="standalone",
    cpu="ps7_cortexa9_0",
    domain_name=domain_name,
)

platform.build()

xpfm = workspace / platform_name / "export" / platform_name / f"{platform_name}.xpfm"
print("XPFM:", xpfm)

app = client.create_app_component(
    name=app_name,
    platform=str(xpfm),
    domain=domain_name,
    template="hello_world",
)

app_src_dir = app_dir / "src"
src_main = root / "software" / "zynq_baremetal" / "main.c"
dst_main = app_src_dir / "main.c"
src_abi_header = root / "software" / "zynq_baremetal" / "cnn_accel_abi.h"
dst_abi_header = app_src_dir / "cnn_accel_abi.h"
src_runtime = root / "software" / "zynq_baremetal" / "cnn_programmable_runtime.c"
dst_runtime = app_src_dir / "cnn_programmable_runtime.c"
src_runtime_header = root / "software" / "zynq_baremetal" / "cnn_programmable_runtime.h"
dst_runtime_header = app_src_dir / "cnn_programmable_runtime.h"
dst_hello = app_src_dir / "helloworld.c"
user_config = app_src_dir / "UserConfig.cmake"
hello_cmake = app_src_dir / "Hello_worldExample.cmake"
cmake_file = app_src_dir / "CMakeLists.txt"

for source in (src_main, src_abi_header, src_runtime, src_runtime_header):
    if not source.exists():
        raise FileNotFoundError(f"Missing source file: {source}")

shutil.copyfile(src_main, dst_main)
shutil.copyfile(src_abi_header, dst_abi_header)
shutil.copyfile(src_runtime, dst_runtime)
shutil.copyfile(src_runtime_header, dst_runtime_header)

src_generated = root / "software" / "zynq_baremetal" / "generated"
dst_generated = app_src_dir / "generated"

if dst_generated.exists():
    shutil.rmtree(dst_generated)

if src_generated.exists():
    shutil.copytree(src_generated, dst_generated)
    print(f"Copied generated headers to {dst_generated}")
else:
    raise FileNotFoundError(f"Missing generated headers directory: {src_generated}")

if user_config.exists():
    text = user_config.read_text()
    text = text.replace('"helloworld.c"', '"main.c" "cnn_programmable_runtime.c"')
    user_config.write_text(text)
else:
    raise FileNotFoundError(f"Missing Vitis source config: {user_config}")

if dst_hello.exists():
    dst_hello.unlink()

if cmake_file.exists():
    text = cmake_file.read_text()
    text = text.replace("include(${CMAKE_CURRENT_SOURCE_DIR}/Hello_worldExample.cmake)\n", "")
    cmake_file.write_text(text)

if hello_cmake.exists():
    hello_cmake.unlink()

app.build()

elf = workspace / app_name / "build" / f"{app_name}.elf"

if not elf.exists():
    raise RuntimeError(f"Vitis app build did not produce ELF: {elf}")

print("")
print("Vitis bare-metal app build done.")
print("ELF:")
print(elf)
print("")
