# bb Dealership (Standalone)

Sistema de concessionária onde:
- Todos podem ver lista de veículos e fazer test-drive.
- Apenas jogadores com o job configurado (`cardealer` por padrão) podem vender.
- Comissão automática para o vendedor + depósito do valor total em conta de sociedade.

## Funcionalidades
- Test drive temporizado com cooldown.
- Limites de preço e verificação anti-abuso.
- Spawn inteligente (procura vaga livre).
- Comissão configurável.
- Whitelist opcional para test drive.
- Integração com `qbx_vehicles`, `qbx_vehiclekeys`, `Renewed-Banking` (opcional), `ox_lib`.

## Instalação
1. Coloca a pasta `custom_dealership` em `[standalone]`.
2. Garante dependências:
   - `ox_lib`
   - `qbx_core`
   - `qbx_vehicles`
   - `qbx_vehiclekeys` (opcional para chaves)
   - `Renewed-Banking` (se quiser sociedade)
3. Adiciona no `server.cfg` (após dependências):
```
ensure custom_dealership
```
4. Ajusta `config.lua` conforme necessário.

## Uso In-Game
- Aproxima-te da área do showroom (center + radius definidos no config).
- Pressiona `E` ou usa o alvo nos carros (se `UseTarget = true`).
- Seleciona veículo → Test Drive ou (se dealer) Vender.
- Dealer introduz ID do comprador + preço.

## Configuração Chave (config.lua)
| Campo | Descrição |
|-------|-----------|
| `DealerJob` | Job necessario para vender |
| `CommissionRate` | Percentagem para o vendedor |
| `SocietyAccount` | Conta banco sociedade |
| `PublicBrowse` | Todos podem ver lista |
| `EnableTestDrive` | Ativa test drive |
| `TestDriveMinutes` | Duração em minutos |
| `SpawnPoints` | Locais spawn pós compra |
| `ShowroomVehicles` | Veículos de exposição |
| `MinPrice/MaxPrice` | Limites de negociação |
| `SaleCooldown` | Anti spam de vendas |

## Segurança / Anti-Abuso
- Verifica job do vendedor no servidor.
- Verifica limites de preço (20%–500% do preço base).
- Refunde comprador se spawn falhar.
- Cooldowns para vendas e test drives.

## Extensões Futuras (Ideias)
- Logs em Discord webhook.
- Financiamento parcelado.
- Gestão de stock / tempo de entrega.
- UI NUI personalizada.

## Suporte
Ajusta os modelos em `ShowroomVehicles` e certifica que existem em `qbx_vehicles` com preço.

Bom roleplay! 🚗
