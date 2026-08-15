--
--  Copyright (C) 2026, RREE
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
--

package ESPIDF.Driver.SPI with Pure is

   type spi_host_device_t is (SPI1_Host, SPI2_Host, SPI3_Host)
     with Convention => C;
   for spi_host_device_t use (SPI1_Host => 0, SPI2_Host => 1, SPI3_Host => 2);

   type spi_dma_chan_t is (SPI_DMA_DISABLED, SPI_DMA_CH_AUTO)
     with Convention => C;
   for spi_dma_chan_t use (SPI_DMA_DISABLED => 0, SPI_DMA_CH_AUTO => 3);
   --  SPI_DMA_CH1/CH2 (ESP32-only legacy fixed-channel selection,
   --  values 1/2) are intentionally not exposed in v1 -- SPI_DMA_CH_AUTO
   --  is the ESP-IDF-recommended default on all current targets.

   type soc_periph_spi_clk_src_t is new int;
   --  Values are imported from the C shim.

   SPI_CLK_SRC_DEFAULT : constant soc_periph_spi_clk_src_t
     with Import, Convention => C, External_Name => "__enum_SPI_CLK_SRC_DEFAULT";

   SPI_CLK_SRC_APB     : constant soc_periph_spi_clk_src_t
     with Import, Convention => C, External_Name => "__enum_SPI_CLK_SRC_APB";
   --  On ESP32 both currently alias the same underlying value
   --  (SOC_MOD_CLK_APB); kept as two names to match the C header.

   subtype spi_clock_source_t is soc_periph_spi_clk_src_t;

end ESPIDF.Driver.SPI;
