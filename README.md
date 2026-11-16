# pages

Static pages shared with friends, served at https://m41w4r3exe.github.io/pages/<slug>/.

Publish or update one page:

```bash
bash publish.sh path/to/page.html <slug>
```

Each page lives in `<slug>/index.html`. Pages carry a noindex tag.

Put a password in front of a page (company numbers, private lists):

```bash
STATICRYPT_PASSWORD='...' bash publish.sh path/to/page.html <slug> --password
```

The page is encrypted with [StatiCrypt](https://github.com/robinmoisson/staticrypt)
(AES-256) before it is committed, so the repo holds only ciphertext and a password
prompt. Without `STATICRYPT_PASSWORD` the script asks for the password in the
terminal. All encrypted pages share the salt in `.staticrypt.json`, so "Remember me"
on one page opens the others that use the same password. The ciphertext is public,
so use 14+ characters.

Encrypting a page that was public before does not remove its old versions from
the git history (the script warns). An encrypted page is never republished without
`--password` (the script refuses). Encrypted pages show the title "Protected page".
