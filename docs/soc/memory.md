# ROM and RAM

ROM is16 KiB at physical0. `ROM_IMAGE` is a byte-per-line hex file, generated
from flat assembler binaries. All unspecified ROM bytes are zero (illegal
instructions), and initialization is a synthesizable FPGA ROM inference using
`$readmemh`, not a testbench replacing CPU fetch. Writes return SLVERR.

RAM is128 KiB at0x10000. The AXI router **instantiates the existing**
`ringisa_ram_fabric`: each physical beat uses its validate/transfer/response
protocol, with byte enables. No duplicate CPU or software-backed hardware memory.
The loader port is disabled in the SoC; boot code initializes every location it
uses. Content is unspecified before initialization and preserved across reset.
Page-table entries intended invalid must explicitly be zeroed; uninitialized
RAM is not a valid empty page table.

Ordinary logical accesses may cross32-bit beats and4 KiB pages. All translations
are completed by the CPU before any physical transaction. All enabled PA bytes
are range checked by the adapter before stores. Sparse translated byte addresses
remain supported; single-byte beats preserve the order of byte indices. Devices
require one naturally aligned32-bit register access, with side effects once.
ROM->RAM mixed reads are allowed if every PA is mapped; ROM/RAM boundaries,
unknown high PA, malformed AXI accesses and peripheral offsets are covered by
directed tests. There is no ECC, DDR controller, external cache or power-failure
persistence guarantee. Neither generic synthesis cells nor initialized ROM
simulation establish FPGA block-RAM resource fit.

The subsequent [storage inference improvement](storage.md) gives RAM an
explicit synchronous read port and one extra read-back cycle per enabled byte.
The transaction contract, full-range validation and reset retention stay the
same. Standalone128 KiB ECP5 RAM mapping now uses64 DP16KD blocks; this does not
establish complete SoC device fit or timing closure.
