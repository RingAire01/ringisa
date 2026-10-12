# SoC address map (generated)

| Region | Physical base | Bytes | Writes |
|---|---|---|---|
| ROM | `0x0000000000000000` | 16384 | False |
| RAM | `0x0000000000010000` | 131072 | True |
| UART | `0x0000000000100000` | 4096 | True |
| TIMER | `0x0000000000101000` | 4096 | True |
| IRQ | `0x0000000000102000` | 4096 | True |

## UART

| Register | Byte offset |
|---|---|
| TX | `0x000` |
| RX | `0x004` |
| STATUS | `0x008` |
| CONTROL | `0x00c` |
| DIVISOR | `0x010` |

## TIMER

| Register | Byte offset |
|---|---|
| COUNT | `0x000` |
| COMPARE | `0x004` |
| CONTROL | `0x008` |
| PENDING | `0x00c` |

## IRQ

| Register | Byte offset |
|---|---|
| PENDING | `0x000` |
| MASK | `0x004` |
| ACK | `0x008` |
| ACTIVE | `0x00c` |
