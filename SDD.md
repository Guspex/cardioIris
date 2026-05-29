# Specification-Driven Development (SDD)
## Sistema de Monitoramento Cirúrgico Cardiológico (IRIS-CardioFlow)

---

## 1. Visão Geral do Sistema
O **IRIS-CardioFlow** é uma aplicação de interoperabilidade médica projetada para unificar e monitorar o fluxo de pacientes cardiológicos em três estados críticos: **Aguardando Cirurgia**, **Em Cirurgia**, e **Pós-Cirúrgico**. 

O sistema é agnóstico a hospitais, utilizando padrões globais de saúde (**HL7 v2** e **FHIR**) transformados nativamente para **SDA (Smart Data Architecture)**, persistidos no InterSystems IRIS 2026 e expostos em dashboards analíticos em tempo real.

---

## 2. Arquitetura da Solução (Interoperabilidade IRIS)

A aplicação seguirá o padrão clássico de Produção do InterSystems IRIS (Bus, Process, Operation):
[Fontes Externas]
│
├── (HL7 v2 ADT/ORM) ──> [BS_HL7_Inbound] ──┐
└── (FHIR REST API)  ──> [BS_FHIR_Inbound] ─┼─> [BP_Cardio_Orchestrator] ──> [BO_SDA_Persist] ──> [IRIS DB (SQL/SDA)] ──> [Dashboards]


### 2.1. Business Services (BS)
* `BS_HL7_Inbound`: Recebe mensagens HL7 (ex: `ADT^A08` para atualização de status, `ORM^O01` para agendamento cirúrgico) via TCP/IP ou File.
* `BS_FHIR_Inbound`: Endpoint REST que estende o repositório FHIR do IRIS para receber recursos como `Encounter`, `Procedure` e `Observation`.

### 2.2. Business Process (BP)
* `BP_Cardio_Orchestrator`: O coração da lógica de negócio (BPL). 
    * Identifica a origem do dado (HL7 ou FHIR).
    * Executa as Data Transformations (DTL) específicas para converter o payload em **SDA3** (ex: `HL7ToSDA3` ou `FHIRToSDA3`).
    * Normaliza as regras de transição de status (`Aguardando` -> `Em Cirurgia` -> `Pós-Op`).

### 2.3. Business Operations (BO)
* `BO_SDA_Persist`: Recebe o objeto SDA3 consolidado, utiliza as classes do pacote `HS.SDA3` (HealthShare/IRIS for Health) para processar, validar e salvar o registro clínico no banco de dados do IRIS.
* `BO_Dashboard_Feeder`: (Opcional/Gatilho) Notifica via WebSocket ou atualiza tabelas de *Staging* otimizadas para os cubos do IRIS BI / Columnar Index.

---

## 3. Estrutura de Agentes (Prompt Codex / IRIS-Agentic-DEV)

Para a construção orientada a agentes via MCP (Model Context Protocol), o desenvolvimento será dividido em sub-agentes especializados.

### 🤖 Agent 1: Interoperability Architect (The Builder)
* **Skill Principal**: Domínio absoluto de ObjectScript, BPL (Business Process Language) e DTL (Data Transformation Language).
* **Escopo**: 
    * Criar as classes de Produção (`CardioFlow.Production`).
    * Desenvolver o `BP_Cardio_Orchestrator` garantindo o gerenciamento de sessões e tratamento de erros.
    * Mapear os segmentos HL7 (ex: `PV1-18` para Patient Status) e elementos FHIR (ex: `Procedure.status`) para os nós corretos do contêiner SDA3.

### 🤖 Agent 2: Data & Analytics Specialist (The Data Master)
* **Skill Principal**: Modelagem SQL, IRIS BI (DeepSee/Analytic Cubes), Columnar Storage (novidade IRIS 2026) e REST APIs.
* **Escopo**:
    * Modelar a tabela de visualização rápida de status cirúrgico.
    * Criar três cubos analíticos ou visões baseadas nos status:
        1.  *Painel Pré-Op*: Tempo de espera, criticidade (fila).
        2.  *Painel Intra-Op*: Tempo de sala de cirurgia, equipe médica alocada.
        3.  *Painel Pós-Op*: Tempo de recuperação, alertas de sinais vitais.
    * Expor os dados via endpoints REST seguros (`/api/cardio/dashboards/...`).

### 🤖 Agent 3: DevOps & QA Engineer (The Guardian)
* **Skill Principal**: Docker multi-estágio, GitHub Actions, ObjectScript Unit Testing (`%UnitTest.TestCase`).
* **Escopo**:
    * Configurar o ambiente isolado em Docker usando a imagem do `intersystems/iris-community:2026.1`.
    * Escrever scripts de carga inicial de dados (`Installer.cls`) para provisionar o Namespace, ativar o suporte a FHIR/SDA e subir a Produção automaticamente.
    * Garantir a pipeline de CI/CD que valida a compilação do código a cada push.

---

## 4. Requisitos de Implementação Técnica

### 4.1. Mapeamento e Normalização (SDA)
Toda entrada será convertida para o formato de contêiner SDA (`HS.SDA3.Container`).
* O status do paciente será rastreado através da propriedade de extensão ou pelo mapeamento do `Encounter` / `Patient` dentro da estrutura do SDA para refletir exatamente os três estados do workflow.

### 4.2. Persistência e Otimização (IRIS 2026)
* Utilizar **Tabelas Columnar** para as métricas dos dashboards, garantindo agregação em milissegundos para os painéis de controle do hospital.

---

## 5. Estrutura do Repositório (GitHub)

O código gerado pelos agentes deve seguir estritamente a estrutura abaixo:

├── .github/
│   └── workflows/
│       └── iris-ci.yml         # Pipeline automatizada de compilação e testes
├── docker/
│   ├── Dockerfile
│   └── docker-compose.yml
├── src/
│   ├── CardioFlow/
│   │   ├── Production.cls      # Configuração da Produção
│   │   ├── BS/                 # Business Services (HL7 / FHIR)
│   │   ├── BP/                 # BPL Orquestrador
│   │   ├── BO/                 # Operações de Banco e SDA
│   │   ├── DTL/                # Mapeamentos HL7/FHIR -> SDA3
│   │   ├── API/                # Despachante REST para os Dashboards
│   │   └── Analytics/          # Definição de Cubos/Views do IRIS BI
│   └── Installer.cls           # Script de setup do IRIS (Namespace/WebApps)
├── tests/
│   └── UnitTest/               # Testes unitários (%UnitTest.TestCase)
├── data/
│   ├── sample_hl7.txt          # Massa de teste HL7 v2
│   └── sample_fhir.json        # Massa de teste FHIR r4
├── README.md
└── sdd-cardio-flow.md          # Este documento


---

## 6. Plano de Testes e Validação (QA)

### 6.1. Testes de Integração Automatizados (`%UnitTest`)
Deverá ser criada uma classe `Test.CardioFlow.Integration` que estende `%UnitTest.TestCase`:
* **Método `TestHL7Flow`**: Injeta uma mensagem HL7 no `BS_HL7_Inbound` via código e valida se o registro foi salvo no banco com o status correto.
* **Método `TestFHIRFlow`**: Dispara uma requisição HTTP simulada para o `BS_FHIR_Inbound` e verifica a transformação para SDA.

### 6.2. Script de Execução dos Testes no Docker
```objectscript
set ^UnitTestRoot = "/usr/irissys/tests"
do ##class(%UnitTest.Manager).RunTest("UnitTest/", "/nodebug/load/save")
7. Instruções para os Agentes (Prompt de Inicialização)
"Atuem em conjunto utilizando as regras definidas neste SDD. O agente Builder deve começar gerando a estrutura de classes e o instalador básico. O Data Master criará os schemas de dados para os dashboards assim que o namespace estiver pronto. O Guardian validará cada etapa escrevendo o Dockerfile correspondente e garantindo que o build passe limpo na imagem IRIS Community 2026."