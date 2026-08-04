<?php

namespace App\State;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProcessorInterface;
use App\Entity\User;
use Symfony\Component\DependencyInjection\Attribute\Autowire;
use Symfony\Component\PasswordHasher\Hasher\UserPasswordHasherInterface;

/**
 * Hashes the plaintext password from registration before delegating to
 * Doctrine's persist processor, so a plaintext password never reaches the
 * database and never leaves this class.
 *
 * @implements ProcessorInterface<User, User>
 */
final class UserRegisterProcessor implements ProcessorInterface
{
    public function __construct(
        #[Autowire(service: 'api_platform.doctrine.orm.state.persist_processor')]
        private readonly ProcessorInterface $persistProcessor,
        private readonly UserPasswordHasherInterface $passwordHasher,
    ) {
    }

    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): mixed
    {
        if (!$data instanceof User) {
            throw new \InvalidArgumentException('UserRegisterProcessor only supports User.');
        }

        if (null !== $data->getPlainPassword()) {
            $data->setPassword($this->passwordHasher->hashPassword($data, $data->getPlainPassword()));
            $data->eraseCredentials();
        }

        return $this->persistProcessor->process($data, $operation, $uriVariables, $context);
    }
}
