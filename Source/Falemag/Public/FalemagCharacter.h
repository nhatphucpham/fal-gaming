#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Character.h"
#include "FalemagCharacter.generated.h"

class UCameraComponent;
class UInputAction;
class USpringArmComponent;
struct FInputActionValue;

UCLASS()
class FALEMAG_API AFalemagCharacter : public ACharacter
{
	GENERATED_BODY()

public:
	AFalemagCharacter();
	virtual void SetupPlayerInputComponent(UInputComponent* PlayerInputComponent) override;

protected:
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Camera")
	TObjectPtr<USpringArmComponent> CameraBoom;

	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Camera")
	TObjectPtr<UCameraComponent> FollowCamera;

	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Input")
	TObjectPtr<UInputAction> MoveAction;

	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Input")
	TObjectPtr<UInputAction> LookAction;

	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Input")
	TObjectPtr<UInputAction> JumpAction;

private:
	void Move(const FInputActionValue& Value);
	void Look(const FInputActionValue& Value);
};
