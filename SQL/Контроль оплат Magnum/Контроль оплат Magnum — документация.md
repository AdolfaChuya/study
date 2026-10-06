# Контроль оплат Magnum

Сверяет платёжные проводки Magnum E-com из учётной системы с заявками на оплату по договору Magnum в IBSO. Записи сопоставляются по Kaspi ID. Отчёт показывает оплаты, которые есть с обеих сторон, есть только в учёте или есть только в IBSO. Данные берутся с 01.01.2025.

## 1. Шапка

| Поле | Описание |
|------|----------|
| **Коннект** | Starrocks |
| **Сложность** | Низкая |
| **Источники** | ERP (S0234 — контроль платежей Kaspi), IBSO (S06) |
| **Ссылка** | — |

## 2. Источники данных

| № | Таблица / Представление | Схема | Назначение |
|----|------------------------|-------|------------|
| 1 | `KASPI_PAYMENT_CONTROL` | `S0234` | Проводки Magnum E-com (сторона учёта), история изменений по `S$CHANGE_DATE` |
| 2 | `S06_Z_KAS_REQUEST_DK` | `BI_VIEW` | Заявки на оплату в IBSO по договорам ДК |
| 3 | `Z_FT_MONEY` | `S06` | Справочник валют IBSO (краткий код валюты) |

## 3. Схема связей

```
KASPI_PAYMENT_CONTROL (ECOM)        — последняя версия записи по KASPI_ID
    └─ OUTER JOIN (Qlik) ON ID = 'MagnumEcom_' & KASPI_ID
S06_Z_KAS_REQUEST_DK (IBS)
    └─ INNER JOIN Z_FT_MONEY (M)  ON IBS.VALUTA = CAST(M.ID AS VARCHAR)
```

## 4. Структура данных

**Часть 1: ECOM — проводки Magnum (учёт)**
- **Источник:** `S0234.KASPI_PAYMENT_CONTROL`
- **Дедупликация:** для каждого `KASPI_ID` берётся последняя запись: `ROW_NUMBER() OVER (PARTITION BY KASPI_ID ORDER BY S$CHANGE_DATE DESC) = 1`.
- **Фильтры:** `PERIOD >= 2025-01-01`
- **Признак:** `ECOM_DK = 'MagnumEcom'`

**Часть 2: IBSO — заявки на оплату**
- **Источник:** `BI_VIEW.S06_Z_KAS_REQUEST_DK` + справочник валют `S06.Z_FT_MONEY`
- **Фильтры:** `TYPE_DK = '166405524307'` (тип договора Magnum), `DATE_REQ >= 2025-01-01`
- **Признак:** `IBSO_DK = 'MagnumEcom'`, `IBSO_KHE_DK = 7777` (константа)

**Часть 3: RESULT — сверка**
- Части 1 и 2 соединяются в Qlik через OUTER JOIN по ключу `ID = 'MagnumEcom_' & Kaspi ID`. В IBSO Kaspi ID хранится в поле `NUM`.
- Если с одной стороны записи нет, все её поля заполняются значением `'-'`. По этому признаку в отчёте видно:
  - `ECOM_KASPI_ID = '-'` — заявка есть в IBSO, проводки в учёте нет;
  - `IBSO_KASPI_ID = '-'` — проводка есть в учёте, заявки в IBSO нет;
  - обе стороны заполнены — оплата сопоставлена.

## 5. Ключевые поля

| Поле | Источник / Логика |
|------|-------------------|
| `ID` | Вычисляемое: `DK & '_' & KASPI_ID`, ключ сверки |
| `ECOM_KASPI_ID` | `KASPI_PAYMENT_CONTROL.KASPI_ID`; пустое значение → `'-'` |
| `ECOM_DATE` | `KASPI_PAYMENT_CONTROL.PERIOD` |
| `ECOM_NUM_DOG` | `KASPI_PAYMENT_CONTROL.NOMER_DOCUMENTA` — номер документа |
| `ECOM_ACCOUNT_DT` / `_KT` | `SCHET_DEBET` / `SCHET_CREDIT` — счета дебета и кредита |
| `ECOM_ANALYTICS_DT1/DT2/KT1/KT2` | `ANALYTIKA_DT1/DT2/KT1/KT2` — аналитики проводки |
| `ECOM_AMOUNT` | `KASPI_PAYMENT_CONTROL.CREDIT` — сумма по кредиту |
| `ECOM_CURRENCY` | `KASPI_PAYMENT_CONTROL.VALYUTA` |
| `ECOM_BIN` | `KASPI_PAYMENT_CONTROL.BIN` |
| `IBSO_KASPI_ID` | `S06_Z_KAS_REQUEST_DK.NUM`; пустое значение → `'-'` |
| `IBSO_DATE_REQ` | `S06_Z_KAS_REQUEST_DK.DATE_REQ` — дата заявки |
| `IBSO_KHE_DK` | Константа `7777` |
| `IBSO_STATE` | `S06_Z_KAS_REQUEST_DK.STATE_ID` — статус заявки |
| `IBSO_AMOUNT` | `S06_Z_KAS_REQUEST_DK.SUMM_PAY` |
| `IBSO_CURRENCY` | `Z_FT_MONEY.C_CUR_SHORT` |
| `IBSO_INIT_NAME` | `S06_Z_KAS_REQUEST_DK.INIT_NAME` — инициатор |
| `IBSO_NAZN` | `S06_Z_KAS_REQUEST_DK.NAZN_PLAT` — назначение платежа |
| `IBSO_SUPPLIER_BIN` / `_NAME` | `SUPPLIER_IN` / `SUPPLIER_NAME` — БИН и название поставщика |

## 6. Бизнес-логика

| Ситуация | Как выглядит в RESULT |
|----------|----------------------|
| Оплата есть и в учёте, и в IBSO | Заполнены поля ECOM_* и IBSO_* |
| Оплата есть только в учёте | Все поля IBSO_* = `'-'` |
| Заявка есть только в IBSO | Все поля ECOM_* = `'-'` |

- Тип договора Magnum в IBSO: `TYPE_DK = '166405524307'`.
- В учёте используется только сумма по кредиту. Поля `DEBET_AMOUNT` и `DEBET_CURRENCY` в скрипте закомментированы.

## 7. Примечания

- **Записи без Kaspi ID:**
  - В ECOM все записи с пустым `KASPI_ID` попадают в одну партицию `ROW_NUMBER`, и из них остаётся только одна. Остальные теряются.
  - В IBSO все заявки без `NUM` получают один и тот же ключ `MagnumEcom_-`. При OUTER JOIN они перемножаются с ECOM-записью с тем же ключом, и строк становится больше, чем на самом деле.
- **Дубли в IBSO:** заявки не дедуплицируются. Если у одного `NUM` несколько заявок (например, повторная после отказа), строка учёта размножится.
- **Числовые поля:** суммы и даты с отсутствующей стороны заменяются текстом `'-'`, поэтому поле содержит и числа, и текст. Сумму в UI лучше считать через `Sum()`: текстовые значения при суммировании игнорируются.
- **Нет сравнения сумм:** флага расхождения (`ECOM_AMOUNT ≠ IBSO_AMOUNT`) в скрипте нет. Если он нужен, его нужно считать в UI.
- **Валюты:** соединение с `Z_FT_MONEY` — INNER JOIN. Заявки с валютой, которой нет в справочнике, не попадут в отчёт.
- **Обновление:** полная перезагрузка при каждом reload, инкрементальной загрузки нет.
