#### ts-error-prettifier.nvim
Formats complex TypeScript type errors in Neovim diagnostics for improved readability.

#### Requirements
- Neovim 0.9 or later
- tsserver via nvim-lspconfig
- typescript-language-server installed globally or locally:

```
npm install -g typescript typescript-language-server
```

Place the plugin at:
```
~/.config/nvim/lua/ts-error-prettifier.lua
```

Add this line to your ```init.lua```
```
require("ts-error-prettifier").setup()
```

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
