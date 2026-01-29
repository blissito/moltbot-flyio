# MoltBot Development Notes

## Recordatorios para Bliss

- [ ] **Explicar el método `tee` para escribir archivos via SSH en Fly.io** - Por qué `fly ssh console -C "cat > file"` no funciona pero `echo "content" | fly ssh console -C "tee file"` sí.

## TODOs

- [ ] Validar formato de API keys y tokens antes de continuar:
  - Anthropic API key: debe empezar con `sk-ant-`
  - OpenAI API key: debe empezar con `sk-`
  - Telegram Bot Token: formato `123456789:ABC...` (números:alfanumérico)
  - Discord Bot Token: formato base64-like largo
  - Slack Bot Token: debe empezar con `xoxb-`
  - Slack App Token: debe empezar con `xapp-`
