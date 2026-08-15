# espidf_driver_spi — Design & Implementation Plan

Ada bindings for ESP-IDF's SPI master driver (`driver/spi_master.h`),
following the conventions established by `godunko/espidf` (root
types/error code) and `godunko/espidf_driver_i2c` (the sibling I2C
binding this crate mirrors directly).

## Architecture

Two crates, longer-term:

```
espidf_driver_spi   -- thin, faithful binding to ESP-IDF's driver/spi_master.h (this repo, now)
espidf_hal_spi      -- adapter: implements Ada_Drivers_Library's HAL.SPI on top of it (later, Stage 9)
```

`espidf_driver_spi` depends on `espidf` (root types/error code), exactly
like `espidf_driver_i2c` does.

### Binding conventions (matching `espidf_driver_i2c`)

- **Package naming**: `ESPIDF.Driver.SPI` (shared enums/types) +
  `ESPIDF.Driver.SPI.Master` (the actual bindings), mirroring
  `ESPIDF.Driver.I2C` / `ESPIDF.Driver.I2C.Master`. ESP-IDF has a separate
  `driver/spi_slave.h`; slave mode is out of scope for v1 (a hypothetical
  future `ESPIDF.Driver.SPI.Slave` would live alongside).
- **Errors**: every binding function returns `ESPIDF.esp_err_t` directly
  — the raw C error code, unwrapped. No coarse status enum, no
  `Last_Error` side-channel.
- **Naming**: functions and types keep their literal C names
  (`spi_bus_add_device`, `spi_device_interface_config_t`, ...) as Ada
  identifiers — a maximally faithful thin binding, not an Ada-idiomatic
  wrapper.
- **Resource lifetime**: plain functions with `in out` handle parameters,
  nulled on success (matches `i2c_del_master_bus`/`i2c_master_bus_rm_device`).
  No `Ada.Finalization` controlled types.
- **Buffers**: `A0B.Types.Arrays.Unsigned_8_Array` — the same ecosystem
  `espidf_gnat_runtime`/`a0b-tools` already pull into `ESP32-Ada`.
- **GPIO pins**: `ESPIDF.Driver.gpio_num_t` (already defined in the root
  `espidf` crate, currently carrying a `-- XXX Move to GPIO driver` TODO
  from the author — use as-is).
- **Timeouts**: `Duration`, converted internally to whatever unit the C
  API wants, with a documented "wait forever" sentinel.
- **Config structs**: represented as opaque `Storage_Array` blobs, sized
  via a C-side `sizeof()` exported as a linkable constant (e.g.
  `__ada_sizeof_spi_bus_config_t`), and populated through a small
  companion **C shim file** with one field-setter function per struct
  (`__ada_spi_bus_config_t__initialize(...)`) that does plain
  `Configuration->field = value;` assignments against the real ESP-IDF
  header. The C compiler handles layout/padding/bitfields, so the binding
  never hand-encodes them and stays immune to ESP-IDF struct changes
  across versions. Enum values that aren't guaranteed-stable small ints
  (SoC-clock-source enums) get the same treatment via `__enum_<NAME>`
  exported constants rather than hand-copied numeric literals.
- **Build**: mixed Ada+C `library project`, `with "espidf.gpr"`, extends
  `ESPIDF.Compiler`, `Library_Name` `"espidf_driver_spi"` — deliberately
  *not* `ada`-prefixed like `espidf_driver_i2c`'s `"adaespidf_driver_i2c"`;
  our own choice, diverging from that convention.
- **`alire.toml`**: minimal — `depends-on espidf = "*"`. No `selftest/`
  for now (deferred, see Stage 1 note below and Stage 7).

### Why `espidf_hal_spi` is a separate crate (Stage 9)

ESP-IDF's SPI master driver and `HAL.SPI` model *chip select* completely
differently:

- **ESP-IDF**: a `spi_bus_config_t` describes the shared MOSI/MISO/SCLK
  lines once; each *device* on the bus (`spi_device_interface_config_t`)
  gets its own CS GPIO, clock speed, mode and queue depth, and the driver
  toggles CS automatically around every transaction.
- **Ada_Drivers_Library's `HAL.SPI.SPI_Port`**: models a single
  point-to-point channel with *no* CS concept at all. Peripheral drivers
  in ADL either assume the port is permanently selected, or toggle a raw
  `GPIO_Point` themselves before/after calling `Transfer`.

So a single ESP-IDF *device handle* (bus + CS + speed + mode) is the
natural match for one `HAL.SPI.SPI_Port` instance — not the bus as a
whole. `espidf_driver_spi` exposes bus and device as separate objects
(like ESP-IDF does); `espidf_hal_spi` would wrap *one device handle* per
`SPI_Port`, with a switch to disable ESP-IDF's automatic CS for drivers
that insist on doing it themselves.

No existing precedent in `godunko`'s ecosystem for this adapter layer
(no `espidf_hal_i2c` exists to check the convention against), so it's a
design choice we own, not something to verify against upstream — kept
deferred and separate rather than blocking this crate.

## The real ESP-IDF SPI API surface

From `spi_master.h`/`spi_common.h`/`spi_types.h`:

- `spi_host_device_t`: `SPI1_HOST=0, SPI2_HOST=1, SPI3_HOST=2` — a plain,
  stable, sequential enum. Hand-mirror directly as an Ada enum with a
  representation clause; no `__enum_*` shim needed.
- `spi_clock_source_t` is `soc_periph_spi_clk_src_t` — a SoC-defined
  enum, same shape as I2C's `soc_periph_i2c_clk_src_t`. Needs the
  `__enum_*` shim treatment; exact `SPI_CLK_SRC_*` symbol names to
  confirm in Stage 2.
- `spi_dma_chan_t` values: to confirm alongside the clock-source enum in
  Stage 2.
- `spi_bus_config_t`: messy nested unions for octal/quad-mode pin
  aliasing (`data0_io_num`..`data7_io_num`). v1 scope: only the 5
  classic named fields (`mosi_io_num`, `miso_io_num`, `sclk_io_num`,
  `quadwp_io_num`, `quadhd_io_num`) + `max_transfer_sz`. Octal/quad mode,
  `isr_cpu_id`, `intr_flags` deferred.
- `spi_device_interface_config_t`: v1 scope covers `mode`,
  `clock_speed_hz`, `spics_io_num`, `queue_size`, `input_delay_ns`,
  `command_bits`, `address_bits`, `dummy_bits`. Deferred:
  `duty_cycle_pos`, `cs_ena_pretrans`/`cs_ena_posttrans`, `pre_cb`/
  `post_cb`, `flags`.
- `spi_transaction_t`: `length`/`rxlength` are in **bits**, not bytes
  (unlike I2C's byte-based `read_size`/`write_size` — a real gotcha).
  Also a union: `tx_buffer`/`rx_buffer` (pointer path) vs `tx_data`/
  `rx_data` (4-byte inline short-transfer optimization via
  `SPI_TRANS_USE_TXDATA`/`RXDATA` flags). v1 scope: pointer path only;
  the inline-data optimization is a documented future addition, not a
  correctness gap.
- Timeout is `ticks_to_wait` (FreeRTOS ticks, `portMAX_DELAY` sentinel
  for infinite) — **not milliseconds** like I2C's `xfer_timeout_ms`.
  Needs its own `Duration → ticks` conversion (via `portTICK_PERIOD_MS`).
- Functions in scope: `spi_bus_initialize`, `spi_bus_free`,
  `spi_bus_add_device`, `spi_bus_remove_device`, `spi_device_transmit`,
  `spi_device_polling_transmit`, `spi_device_get_actual_freq`,
  `spi_bus_get_max_transaction_len`.

## Staged plan

### Stage 1 — Crate skeleton ✅
- `alire.toml` mirroring `espidf_driver_i2c`'s structure (see
  conventions above); tags `["embedded", "esp32", "espidf", "driver",
  "spi"]`.
- `espidf_driver_spi.gpr` mirroring `espidf_driver_i2c.gpr`, except
  `Library_Name` `"espidf_driver_spi"` (no `ada` prefix — our choice).
- `espidf` confirmed published in the Alire index (0.1.0) — plain
  `depends-on espidf = "*"` resolves with no pins needed.
- `selftest/` deliberately **not** created yet — deferred to Stage 7
  alongside the real selftest content, rather than scaffolding an empty
  placeholder now.

### Stage 2 — `ESPIDF.Driver.SPI` — shared types ✅
`src/espidf-driver-spi.ads`:
- `spi_host_device_t` → hand-mirrored `SPI1_Host`/`SPI2_Host`/
  `SPI3_Host` enum (confirmed stable: 0/1/2).
- `spi_dma_chan_t` (`spi_common_dma_t`) → also a plain stable enum,
  confirmed no shim needed either: `SPI_DMA_DISABLED=0`,
  `SPI_DMA_CH1=1`/`CH2=2` (ESP32-only legacy, `#if
  CONFIG_IDF_TARGET_ESP32` — not exposed in v1), `SPI_DMA_CH_AUTO=3`
  (exposed).
- `soc_periph_spi_clk_src_t`: confirmed it *does* need the `__enum_*`
  shim treatment — on ESP32 it only has `SPI_CLK_SRC_DEFAULT`/
  `SPI_CLK_SRC_APB`, both aliasing the shared `SOC_MOD_CLK_APB` value,
  not a value safe to hand-copy. Declared as `Import`ed constants
  (`__enum_SPI_CLK_SRC_DEFAULT`/`__enum_SPI_CLK_SRC_APB`); the actual C
  shim providing those symbols is still Stage 6 — this only declares the
  Ada side, consistent with `.ads`-before-shim ordering not mattering
  for compilation (only linking, which isn't attempted until later
  stages).

### Stage 3 — Bus: `spi_bus_initialize`/`spi_bus_free`
- Opaque `Storage_Array`-backed `spi_bus_config_t`, sized via
  `__ada_sizeof_spi_bus_config_t`.
- `Initialize` procedure exposing the v1 field scope above; GPIO params
  typed `ESPIDF.Driver.gpio_num_t`.
- `spi_bus_initialize`/`spi_bus_free` as direct-named functions
  returning `esp_err_t` — note `spi_bus_free` only takes `host_id`, no
  handle, so this is simpler than I2C's bus (no null-out-on-success
  needed).

### Stage 4 — Device: `spi_bus_add_device`/`spi_bus_remove_device`
- Opaque `Storage_Array`-backed `spi_device_interface_config_t`, sized
  via `__ada_sizeof_spi_device_interface_config_t`.
- `Initialize` procedure exposing the v1 field scope above.
- `spi_bus_add_device`/`spi_bus_remove_device` matching
  `i2c_master_bus_add_device`/`i2c_master_bus_rm_device`'s shape
  (`in out spi_device_handle_t`, nulled on success).

### Stage 5 — Transactions
- `spi_transaction_t`: decide whether this goes through the opaque
  Storage_Array + C-shim pattern (safest, matches everything else) or a
  hand-mirrored Ada record — it's flatter than the config structs (no
  bitfields), so a hand-mirror is defensible here specifically; make the
  call when writing this stage and document the reasoning either way.
- `Duration → ticks_to_wait` conversion, confirmed against
  `portTICK_PERIOD_MS`.
- `spi_device_polling_transmit` when `Queue_Size = 1` (lowest latency, no
  ISR round-trip — the right default for sensor/display register
  access), `spi_device_transmit` otherwise.
- Buffer overloads with `A0B.Types.Arrays.Unsigned_8_Array`, mirroring
  I2C's `System.Address`-primitive-plus-array-convenience-overload
  pattern. Remember `length`/`rxlength` are bits: multiply by 8 going in,
  divide coming out.

### Stage 6 — C shim (`src/ada_espidf_spi_master.c`)
`__ada_sizeof_spi_bus_config_t`, `__ada_sizeof_spi_device_interface_config_t`
(and `__ada_sizeof_spi_transaction_t` if Stage 5 goes the opaque-blob
route), matching `__ada_*__initialize` field-setters, `__enum_SPI_CLK_SRC_*`
from Stage 2.

### Stage 7 — selftest
Mirror `espidf_driver_i2c`'s `selftest/` structure. Without guaranteed
SPI loopback hardware, the initial selftest likely only exercises
`spi_bus_initialize`/`spi_bus_free` round-trip, not a full transaction —
real transaction-level correctness needs actual hardware (Stage 8).

### Stage 8 — Real hardware validation
Wire into `ESP32-Ada`/`esp32_template` against the CYD's ILI9341 SPI bus
as the first real consumer. Same lesson as the LX6/LX7 saga in
`ESP32-Ada`'s `doc/build_environment.md`: a clean build is not evidence
of correctness — this crate isn't done until something real has been
clocked out over the wire on actual hardware.

### Stage 9 (deferred, separate crate/repo) — `espidf_hal_spi`

- `SPI_Port` wraps one already-`Add`-ed `SPI_Device` (one bus + CS
  combination); bus/device setup stays in `espidf_driver_spi`, this type
  is purely an interface adapter.
- **16-bit support**: ESP-IDF frames transactions in bytes. `HAL.SPI`'s
  16-bit transfers get implemented by byte-swapping each `UInt16` per
  the device's configured bit order into a scratch byte buffer, calling
  the 8-bit transfer, then unpacking — the same trick most MCU HAL BSPs
  use when their SPI peripheral is natively byte-oriented.
- **Manual-CS mode**: some Ada_Drivers_Library peripheral drivers hold
  their own `HAL.GPIO.GPIO_Point` for chip select and drive it around
  every `Transfer` call, expecting the port itself to be CS-agnostic.
  Setting the device's CS GPIO to "unused" (ESP-IDF's `spics_io_num =
  -1`) disables the driver's automatic CS entirely, so the adapter
  doesn't need to know CS exists in this mode at all — the caller wires
  up an independent `HAL.GPIO` CS pin exactly as the peripheral driver
  expects. For newly-written or already-ESP32-targeted drivers, prefer a
  real CS pin and let ESP-IDF manage it — one less GPIO toggle per call,
  and strictly more correct on chips with hardware CS setup/hold timing.

Re-validate all of the above against whatever `hal` crate version is
actually pinned once this stage is picked up — `espidf_driver_spi` should
stand on its own first.
