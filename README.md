#### How to Install and Use the Plugin
Here is how you can install this plugin using lazy.nvim (recommended) or packer.nvim. The key is to place the plugin code where Neovim can find it and then call the setup function.

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
