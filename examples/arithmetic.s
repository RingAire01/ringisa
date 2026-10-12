CONST128 R1, 0xffffffffffffffffffffffffffffffff
MOVI R2, 1
ADD.256 R3, R1, R2
VADD.8 R4, R1, R2
MOVI R5, 256
ST.256 R3, R5, 0
LD.256 R6, R5, 0
WFI
