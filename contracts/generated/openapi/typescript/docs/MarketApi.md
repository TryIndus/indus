# MarketApi

All URIs are relative to *http://localhost*

| Method | HTTP request | Description |
|------------- | ------------- | -------------|
| [**getMarketHistory**](MarketApi.md#getmarkethistory) | **GET** /v1/market/history/{symbol} | Return one year of daily closing prices for an instrument. |
| [**getMarketSummary**](MarketApi.md#getmarketsummary) | **GET** /v1/market/summary | Return index quotes and the authenticated user\&#39;s watchlist snapshot. |



## getMarketHistory

> MarketHistory getMarketHistory(symbol)

Return one year of daily closing prices for an instrument.

### Example

```ts
import {
  Configuration,
  MarketApi,
} from '';
import type { GetMarketHistoryRequest } from '';

async function example() {
  console.log("🚀 Testing  SDK...");
  const config = new Configuration({
    // Configure HTTP bearer authorization: bearerAuth
    accessToken: "YOUR BEARER TOKEN",
  });
  const api = new MarketApi(config);

  const body = {
    // string
    symbol: symbol_example,
  } satisfies GetMarketHistoryRequest;

  try {
    const data = await api.getMarketHistory(body);
    console.log(data);
  } catch (error) {
    console.error(error);
  }
}

// Run the test
example().catch(console.error);
```

### Parameters


| Name | Type | Description  | Notes |
|------------- | ------------- | ------------- | -------------|
| **symbol** | `string` |  | [Defaults to `undefined`] |

### Return type

[**MarketHistory**](MarketHistory.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: `application/json`, `application/problem+json`


### HTTP response details
| Status code | Description | Response headers |
|-------------|-------------|------------------|
| **200** | A bounded historical price series. |  -  |
| **400** | The request is malformed. |  -  |
| **401** | Authentication is absent or invalid. |  -  |
| **404** | The resource does not exist or is not visible to the caller. |  -  |
| **429** | A request quota was exhausted. |  * Retry-After -  <br>  |
| **502** | A required upstream provider failed or returned invalid data. |  -  |

[[Back to top]](#) [[Back to API list]](../README.md#api-endpoints) [[Back to Model list]](../README.md#models) [[Back to README]](../README.md)


## getMarketSummary

> MarketSummary getMarketSummary()

Return index quotes and the authenticated user\&#39;s watchlist snapshot.

### Example

```ts
import {
  Configuration,
  MarketApi,
} from '';
import type { GetMarketSummaryRequest } from '';

async function example() {
  console.log("🚀 Testing  SDK...");
  const config = new Configuration({
    // Configure HTTP bearer authorization: bearerAuth
    accessToken: "YOUR BEARER TOKEN",
  });
  const api = new MarketApi(config);

  try {
    const data = await api.getMarketSummary();
    console.log(data);
  } catch (error) {
    console.error(error);
  }
}

// Run the test
example().catch(console.error);
```

### Parameters

This endpoint does not need any parameter.

### Return type

[**MarketSummary**](MarketSummary.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: `application/json`, `application/problem+json`


### HTTP response details
| Status code | Description | Response headers |
|-------------|-------------|------------------|
| **200** | A bounded dashboard market snapshot. |  -  |
| **401** | Authentication is absent or invalid. |  -  |
| **429** | A request quota was exhausted. |  * Retry-After -  <br>  |
| **502** | A required upstream provider failed or returned invalid data. |  -  |

[[Back to top]](#) [[Back to API list]](../README.md#api-endpoints) [[Back to Model list]](../README.md#models) [[Back to README]](../README.md)
