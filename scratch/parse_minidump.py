import struct
import os

dmp_path = r"C:\Users\Administrator\AppData\Roaming\com.appmanager.app\app_manager\crashes\crash_20260821_194324.dmp"

with open(dmp_path, "rb") as f:
    data = f.read()

magic = data[:4]
print("Magic:", magic.decode("ascii", errors="ignore"))

num_streams, stream_directory_rva = struct.unpack_from("<II", data, 8)
print("Streams count:", num_streams)

for i in range(num_streams):
    stream_type, data_size, rva = struct.unpack_from("<III", data, stream_directory_rva + i * 12)
    # Stream Type 6 = ExceptionStream, Type 4 = ModuleListStream, Type 3 = ThreadListStream
    if stream_type == 6: # ExceptionStream
        thread_id, _, exception_code, exception_flags, exception_record, exception_addr = struct.unpack_from("<IIIIQQ", data, rva)
        print(f"\n--- EXCEPTION DETECTED ---")
        print(f"Thread ID: {thread_id}")
        print(f"Exception Code: 0x{exception_code:08X}")
        print(f"Exception Address: 0x{exception_addr:16X}")
    elif stream_type == 4: # ModuleList
        num_modules = struct.unpack_from("<I", data, rva)[0]
        print(f"\n--- MODULE LIST ({num_modules} modules) ---")
        mod_offset = rva + 4
        for m in range(min(num_modules, 30)):
            base_of_img, size_of_img, check_sum, time_stamp, name_rva = struct.unpack_from("<QIIII", data, mod_offset + m * 108)
            # read module name string at name_rva (UTF-16LE)
            name_len = struct.unpack_from("<I", data, name_rva)[0]
            name_bytes = data[name_rva + 4 : name_rva + 4 + name_len]
            name_str = name_bytes.decode("utf-16le", errors="ignore")
            print(f"0x{base_of_img:12X} - 0x{base_of_img+size_of_img:12X} : {name_str}")
