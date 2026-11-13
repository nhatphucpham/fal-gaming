#pragma once

#include "CoreMinimal.h"
#include "GameFramework/PlayerController.h"
#include "FalemagPlayerController.generated.h"

class UInputMappingContext;

UCLASS()
class FALEMAG_API AFalemagPlayerController : public APlayerController
{
	GENERATED_BODY()

protected:
	virtual void BeginPlay() override;

	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Input")
	TObjectPtr<UInputMappingContext> InputMappingContext;
};
