--
--  Copyright (C) 2026, RREE
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
--

pragma Ada_2022;

private with System.Storage_Elements;

package ESPIDF.Driver.SPI.Master is

   type spi_bus_config_t is private;

   procedure Initialize
     (Configuration   : out spi_bus_config_t;
      mosi_io_num     : gpio_num_t := -1;
      miso_io_num     : gpio_num_t := -1;
      sclk_io_num     : gpio_num_t := -1;
      quadwp_io_num   : gpio_num_t := -1;
      quadhd_io_num   : gpio_num_t := -1;
      max_transfer_sz : int        := 0);
   --  max_transfer_sz = 0 lets the driver pick its default (4092 bytes
   --  with DMA enabled, or SOC_SPI_MAXIMUM_BUFFER_SIZE without).

   function spi_bus_initialize
     (host_id    : spi_host_device_t;
      bus_config : spi_bus_config_t;
      dma_chan   : spi_dma_chan_t) return esp_err_t
      with Import, Convention => C, Link_Name => "spi_bus_initialize";

   function spi_bus_free
     (host_id : spi_host_device_t) return esp_err_t
      with Import, Convention => C, Link_Name => "spi_bus_free";
   --  Unlike ESPIDF.Driver.I2C.Master's bus, ESP-IDF's spi_bus_free only
   --  takes host_id -- there is no separate bus handle to null out.

private

   sizeof_spi_bus_config_t : constant int
      with Import, Convention => C,
           Link_Name => "__ada_sizeof_spi_bus_config_t";

   type spi_bus_config_t_Storage is
     new System.Storage_Elements.Storage_Array
       (1 .. System.Storage_Elements.Storage_Count
               (sizeof_spi_bus_config_t)) with Convention => C;

   type spi_bus_config_t is record
      Storage : spi_bus_config_t_Storage := [others => 0];
   end record with Convention => C;

end ESPIDF.Driver.SPI.Master;
