#### How to Install and Use the Plugin
Here is how you can install this plugin using lazy.nvim (recommended) or packer.nvim. The key is to place the plugin code where Neovim can find it and then call the setup function.

#### Step 1: Save the Plugin File
First, save the Lua code above into a file. You have two common options:

As a Local Plugin: Save the code to ~/.config/nvim/plugin/ts-error-prettifier.lua. Files in the plugin/ directory are automatically loaded by Neovim at startup. You would also need to set a global variable in your init.lua to enable it.
```
-- in your init.lua
vim.g.ts_error_prettifier_auto_setup = true
```
As a Module (Recommended for Plugin Managers): Save the code to ~/.config/nvim/lua/ts-error-prettifier.lua. This makes it a Lua module that your plugin manager can load.

#### Step 2: Configure Your Plugin Manager
Choose the guide for your plugin manager. The following examples assume you chose Option 2 from Step 1 and saved the file in lua/.

#### lazy.nvim (Recommended)
Add the following spec to your lazy.nvim plugins list. This setup treats your local file as a plugin.
```
-- in your plugins file (e.g., lua/plugins/local.lua)

return {
  {
    -- A path to your local plugin
    '~/.config/nvim/lua/ts-error-prettifier.lua',
    -- Or you can use a more structured path like 'local/ts-error-prettifier'
    -- and place the file in `lua/local/ts-error-prettifier/init.lua`

    -- Load it when a TypeScript file is opened
    ft = { "typescript", "typescriptreact", "javascript", "javascriptreact" },
    config = function()
      -- Call the setup function from your local module
      require('ts-error-prettifier').setup()
    end,
  },
}
```
After adding the code, restart Neovim and run :Lazy sync to install.

#### packer.nvim
Add the following code to your packer.nvim setup.
```
-- in your plugins.lua

use {
  '~/.config/nvim/lua/ts-error-prettifier.lua',
  ft = { "typescript", "typescriptreact", "javascript", "javascriptreact" },
  config = function()
    require('ts-error-prettifier').setup()
  end,
}
```
After adding the code, restart Neovim and run :PackerSync to install.

How It Works
Once installed, the plugin will automatically intercept any error messages coming from tsserver. When it finds a common "Type A is not assignable to Type B" error, it will reformat it into a multi-line, indented block in the diagnostic window (which you can open with vim.diagnostic.open_float() or see on hover).

Before:
```
Type '{ name: string; details: { id: number; active: string; }; }' is not assignable to type '{ name: string; details: { id: number; active: boolean; }; }'.
```
After:
```
❌ Type Mismatch
=================
Got:
{
  name: string;
  details: {
    id: number;
    active: string;
  };
}

Expected:
{
  name: string;
  details: {
    id: number;
    active: boolean;
  };
}
=================
```
