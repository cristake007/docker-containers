<?php

namespace App\State;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProcessorInterface;
use App\Entity\Task;
use App\Entity\User;
use Symfony\Bundle\SecurityBundle\Security;
use Symfony\Component\DependencyInjection\Attribute\Autowire;
use Symfony\Component\Security\Core\Exception\AccessDeniedException;

/**
 * Stamps a newly created Task with the authenticated user as owner. Owner is
 * never part of the GraphQL input (see Task::$owner), so this is the only
 * place ownership is ever assigned.
 *
 * @implements ProcessorInterface<Task, Task>
 */
final class TaskCreateProcessor implements ProcessorInterface
{
    public function __construct(
        #[Autowire(service: 'api_platform.doctrine.orm.state.persist_processor')]
        private readonly ProcessorInterface $persistProcessor,
        private readonly Security $security,
    ) {
    }

    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): mixed
    {
        if (!$data instanceof Task) {
            throw new \InvalidArgumentException('TaskCreateProcessor only supports Task.');
        }

        $user = $this->security->getUser();
        if (!$user instanceof User) {
            throw new AccessDeniedException('A logged-in user is required to create a task.');
        }

        $data->setOwner($user);

        return $this->persistProcessor->process($data, $operation, $uriVariables, $context);
    }
}
