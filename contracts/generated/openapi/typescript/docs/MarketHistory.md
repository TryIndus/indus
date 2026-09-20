
# MarketHistory


## Properties

Name | Type
------------ | -------------
`symbol` | string
`currency` | string
`range` | string
`points` | [Array&lt;MarketHistoryPointsInner&gt;](MarketHistoryPointsInner.md)

## Example

```typescript
import type { MarketHistory } from ''

// TODO: Update the object below with actual values
const example = {
  "symbol": null,
  "currency": null,
  "range": null,
  "points": null,
} satisfies MarketHistory

console.log(example)

// Convert the instance to a JSON string
const exampleJSON: string = JSON.stringify(example)
console.log(exampleJSON)

// Parse the JSON string back to an object
const exampleParsed = JSON.parse(exampleJSON) as MarketHistory
console.log(exampleParsed)
```

[[Back to top]](#) [[Back to API list]](../README.md#api-endpoints) [[Back to Model list]](../README.md#models) [[Back to README]](../README.md)
