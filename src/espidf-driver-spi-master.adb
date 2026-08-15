--
--  Copyright (C) 2026, RREE
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
--

package body ESPIDF.Driver.SPI.Master is

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize
     (Configuration   : out spi_bus_config_t;
      mosi_io_num     : gpio_num_t := -1;
      miso_io_num     : gpio_num_t := -1;
      sclk_io_num     : gpio_num_t := -1;
      quadwp_io_num   : gpio_num_t := -1;
      quadhd_io_num   : gpio_num_t := -1;
      max_transfer_sz : int        := 0)
   is
      procedure Internal
        (Configuration   : out spi_bus_config_t;
         mosi_io_num     : gpio_num_t;
         miso_io_num     : gpio_num_t;
         sclk_io_num     : gpio_num_t;
         quadwp_io_num   : gpio_num_t;
         quadhd_io_num   : gpio_num_t;
         max_transfer_sz : int)
         with Import,
              Convention => C,
              External_Name => "__ada_spi_bus_config_t__initialize";

   begin
      Internal
        (Configuration   => Configuration,
         mosi_io_num     => mosi_io_num,
         miso_io_num     => miso_io_num,
         sclk_io_num     => sclk_io_num,
         quadwp_io_num   => quadwp_io_num,
         quadhd_io_num   => quadhd_io_num,
         max_transfer_sz => max_transfer_sz);
   end Initialize;

end ESPIDF.Driver.SPI.Master;
